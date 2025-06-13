#!/bin/bash

# Exit if any command in the script fails.
set -e

# Pretty-print JSON using jq or json_pp if available.
print_json() {
    file=${1?file}
    if command -v jq >/dev/null 2>&1; then
        jq . "$file" || cat "$file"
    elif command -v json_pp >/dev/null 2>&1; then
        json_pp < "$file" || cat "$file"
    else
        cat "$file"
    fi
}

didkit_url=http://localhost:3000
docker_name="didkit-cli"

if [ -e issuer_key.jwk ]; then
    echo 'Using existing keypair.'
else
    docker run --name $docker_name --rm ghcr.io/spruceid/didkit-cli:latest key generate ed25519 > issuer_key.jwk
    echo 'Generated keypair.'
fi

did=$(docker run --name $docker_name --rm ghcr.io/spruceid/didkit-cli:latest key to did --jwk $(cat issuer_key.jwk))
printf 'DID: %s\n\n' "$did"

verification_method=$(docker run --name $docker_name --rm ghcr.io/spruceid/didkit-cli:latest key to verification-method --jwk  $(cat issuer_key.jwk) key)
printf 'verificationMethod: %s\n\n' "$verification_method"

SUBJECTDID='did:example:d23dd687a7dc6787646f2eb98d0'
ISSUERDID=$did
DATE=`date --utc +%FT%TZ`
CREDID="urn:uuid:"`uuidgen`

cat > credential-unsigned.jsonld <<EOF
{
    "@context": "https://www.w3.org/2018/credentials/v1",
    "id": "$CREDID",
    "type": ["VerifiableCredential"],
    "issuer": "$ISSUERDID",
    "issuanceDate": "$DATE",
    "credentialSubject": {
        "id": "$SUBJECTDID"
    }
}
EOF

cred=$(cat <<-END
{
  "credential": $(cat credential-unsigned.jsonld),
  "options": {
    "verificationMethod": "$verification_method",
    "proofPurpose": "assertionMethod"
  }
}
END
)

echo "$cred" > "cred"

if ! curl -fsS $didkit_url/issue/credentials \
    -H 'Content-Type: application/json' \
    -o credential-signed.jsonld \
    -d "$cred"
then
    echo 'Unable to issue credential.'
    exit 1
fi

echo 'Issued verifiable credential:'
print_json credential-signed.jsonld
echo

verify=$(cat <<-END
  $(cat credential-signed.jsonld),
  "options": {
    "verificationMethod": "$verification_method",
    "proofPurpose": "assertionMethod"
  }
END
)

echo "$verify" > "verify"

if ! curl -fsS $didkit_url/verify/credentials \
    -H 'Content-Type: application/json' \
    -o credential-verify-result.json \
    -d "$verify"
then
    echo 'Unable to verify credential.'
    exit 1
fi
echo 'Verified verifiable credential:'
print_json credential-verify-result.json
echo

cat > presentation-unsigned.jsonld <<EOF
{
    "@context": ["https://www.w3.org/2018/credentials/v1"],
    "id": "http://example.org/presentations/3731",
    "type": ["VerifiablePresentation"],
    "holder": "$did",
    $(cat credential-signed.jsonld | sed -E 's/^.|.$//g')
}
EOF

if ! curl -fsS $didkit_url/issue/presentations \
    -H 'Content-Type: application/json' \
    -o presentation-signed.jsonld \
    -d @- <<EOF
{
  "presentation": $(cat presentation-unsigned.jsonld),
  "options": {
    "verificationMethod": "$verification_method",
    "proofPurpose": "authentication"
  }
}
EOF
then
    echo 'Unable to issue presentation.'
    exit 1
fi
echo 'Issued verifiable presentation:'
print_json presentation-signed.jsonld
echo

verify_presentation_request=$(cat <<-END
{
  $(cat presentation-signed.jsonld | sed -E 's/^.|.$//g'),
  "options": {
    "verificationMethod": "$verification_method",
    "proofPurpose": "authentication"
  }
}
END
)

if ! curl -fsS $didkit_url/verify/presentations \
    -H 'Content-Type: application/json' \
    -o presentation-verify-result.json \
    -d "$verify_presentation_request"
then
    echo 'Unable to verify presentation.'
    exit 1
fi
echo 'Verified verifiable presentation:'
print_json presentation-verify-result.json
echo

