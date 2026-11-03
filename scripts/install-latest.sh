#!/bin/zsh
# Download the unsigned IPA from CI, sign it with the local Personal Team profile and
# install it on the connected iPhone.
#
# Usage: scripts/install-latest.sh [run-id]   (default: latest successful Build run on main)
set -euo pipefail

BUNDLE_ID=xyz.napple.DJIExtract
APP_NAME="DJI Extract.app"
PROFILE_DIR=~/Library/Developer/Xcode/UserData/Provisioning\ Profiles

die() { print -u2 "error: $*"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1. Pick the newest unexpired profile for the bundle ID.
profile="" expiry=0
for p in "$PROFILE_DIR"/*.mobileprovision(N); do
  security cms -D -i "$p" > "$WORK/p.plist" 2>/dev/null || continue
  [[ $(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$WORK/p.plist") == *.$BUNDLE_ID ]] || continue
  exp=$(date -j -f "%a %b %d %T %Z %Y" "$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$WORK/p.plist")" +%s)
  (( exp > expiry )) && { profile=$p; expiry=$exp; cp "$WORK/p.plist" "$WORK/profile.plist"; }
done
[[ -n $profile ]] || die "no provisioning profile for $BUNDLE_ID; build once from Xcode to create one"
(( expiry > $(date +%s) )) || die "profile expired on $(date -r $expiry +%F); build once from Xcode to renew it"
print "Profile: $(/usr/libexec/PlistBuddy -c "Print :Name" "$WORK/profile.plist") (expires $(date -r $expiry +%F))"

plutil -extract Entitlements xml1 -o "$WORK/ent.plist" "$WORK/profile.plist"
identity=$(/usr/libexec/PlistBuddy -c "Print :DeveloperCertificates:0" "$WORK/profile.plist" \
  | openssl x509 -inform der -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)
security find-identity -v -p codesigning | grep -q $identity || die "signing identity $identity is not in the keychain"

# 2. Find a connected device that the profile covers.
devices=$(xcrun devicectl list devices 2>/dev/null)
device=""
for udid in $(/usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$WORK/profile.plist" | sed '1d;$d'); do
  print -r -- "$devices" | grep "$udid" | grep -qE "available|connected" &&{ device=$udid; break; }
done
[[ -n $device ]] || die "no connected device from the profile; connect and unlock the iPhone"

# 3. Download the IPA.
run=${1:-$(gh run list -w Build -b main -s success -L 1 --json databaseId -q '.[0].databaseId')}
[[ -n $run ]] || die "no successful Build run found"
print "Run: $(gh run view $run --json headSha,displayTitle -q '.headSha[0:7] + " " + .displayTitle')"
gh run download $run -n DJIExtract-unsigned-ipa -D "$WORK/dl"
(cd "$WORK" && unzip -q dl/DJIExtract-unsigned.ipa)

# 4. Sign (nested code first, then the app with the profile's entitlements).
app="$WORK/Payload/$APP_NAME"
cp "$profile" "$app/embedded.mobileprovision"
find "$app" -depth \( -name "*.framework" -o -name "*.dylib" \) -exec codesign -f -s $identity {} \;
codesign -f -s $identity --entitlements "$WORK/ent.plist" "$app"
codesign -v --strict "$app"
(cd "$WORK" && zip -qry signed.ipa Payload)

# 5. Install. The device connection sometimes resets mid-transfer; retry once.
xcrun devicectl device install app --device $device "$WORK/signed.ipa" \
  || { print "Install failed; retrying..."; sleep 3; xcrun devicectl device install app --device $device "$WORK/signed.ipa"; }
print "Installed on $device"
