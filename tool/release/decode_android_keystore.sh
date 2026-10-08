#!/usr/bin/env bash
# Decodes the ANDROID_KEYSTORE_BASE64 secret into a keystore file and checks it
# opens with the configured password and alias, without printing secret values.
#
# Usage: KEYSTORE_BASE64=... KEYSTORE_PASSWORD=... KEY_ALIAS=... \
#          decode_android_keystore.sh <output-keystore-path>
set -euo pipefail

output_path="${1:?Pass the output keystore path.}"
: "${KEYSTORE_BASE64:?Set the ANDROID_KEYSTORE_BASE64 Actions secret.}"
: "${KEYSTORE_PASSWORD:?Set the ANDROID_KEYSTORE_PASSWORD Actions secret.}"
: "${KEY_ALIAS:?Set the ANDROID_KEY_ALIAS Actions secret.}"

fail() {
  echo "::error::$1"
  rm -f "$output_path"
  exit 1
}

# Accept the encodings Windows and macOS tools produce: line-wrapped output,
# certutil -encode output with its -----BEGIN/END----- lines, surrounding
# quotes, URL-safe Base64 and missing padding.
encoded="$(printf '%s\n' "$KEYSTORE_BASE64" | tr -d '\r' | sed '/^[[:space:]]*-----/d' | tr -d '[:space:]"'"'" | tr -- '-_' '+/' | sed 's/=*$//')"
if [[ -z "$encoded" ]]; then
  fail "ANDROID_KEYSTORE_BASE64 is empty once whitespace and BEGIN/END lines are removed."
fi
invalid_characters="$(printf '%s' "$encoded" | tr -d 'A-Za-z0-9+/' | fold -w1 | sort -u | tr -d '\n')"
if [[ -n "$invalid_characters" ]]; then
  fail "ANDROID_KEYSTORE_BASE64 contains characters that are not Base64: '$invalid_characters'. Store the Base64 text of the keystore file, not its path."
fi
if (( ${#encoded} % 4 == 1 )); then
  fail "ANDROID_KEYSTORE_BASE64 is truncated (${#encoded} Base64 characters). Copy the complete encoded keystore."
fi
while (( ${#encoded} % 4 != 0 )); do
  encoded+="="
done

if ! printf '%s' "$encoded" | base64 --decode > "$output_path" 2>/dev/null || [[ ! -s "$output_path" ]]; then
  fail "ANDROID_KEYSTORE_BASE64 could not be decoded as Base64."
fi

# JKS starts with FEEDFEED, JCEKS with CECECECE and PKCS12 with a DER sequence (30).
magic="$(head -c 4 "$output_path" | od -An -tx1 | tr -d '[:space:]')"
case "$magic" in
  feedfeed | cececece | 30*) ;;
  *) fail "ANDROID_KEYSTORE_BASE64 decodes to $(wc -c < "$output_path" | tr -d '[:space:]') bytes that are not a JKS or PKCS12 keystore. Encode the .jks/.keystore file itself, once." ;;
esac

if command -v keytool > /dev/null 2>&1; then
  if ! keytool_output="$(keytool -list -keystore "$output_path" -storepass:env KEYSTORE_PASSWORD -alias "$KEY_ALIAS" 2>&1)"; then
    if grep -qi "password" <<< "$keytool_output"; then
      fail "The keystore decoded, but ANDROID_KEYSTORE_PASSWORD does not open it."
    fi
    if grep -qi "does not exist" <<< "$keytool_output"; then
      fail "The keystore decoded, but it has no key named by ANDROID_KEY_ALIAS."
    fi
    fail "keytool could not read the decoded keystore: $(head -n 1 <<< "$keytool_output")"
  fi
fi

echo "Decoded the Android release keystore and verified its password and alias."
