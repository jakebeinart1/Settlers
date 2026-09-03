import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';

const keyID = 'R7AQ2QHN3X';
const issuerID = 'e02eba85-9a60-477a-b3f3-c4d86bbc598d';
const bundleID = 'com.alexchandler.empires';
const keyPath = '/Users/alex/.appstoreconnect/private_keys/AuthKey_' + keyID + '.p8';

const base64url = (value) =>
    Buffer.from(typeof value === 'string' ? value : JSON.stringify(value)).toString('base64url');

function token() {
    const issuedAt = Math.floor(Date.now() / 1000);
    const header = base64url({ alg: 'ES256', kid: keyID, typ: 'JWT' });
    const payload = base64url({
        iss: issuerID,
        iat: issuedAt,
        exp: issuedAt + 600,
        aud: 'appstoreconnect-v1',
    });
    const message = header + '.' + payload;
    const signature = createSign('SHA256')
        .update(message)
        .sign({
            key: readFileSync(keyPath, 'utf8'),
            dsaEncoding: 'ieee-p1363',
        })
        .toString('base64url');
    return message + '.' + signature;
}

async function request(path) {
    const response = await fetch('https://api.appstoreconnect.apple.com' + path, {
        headers: { Authorization: 'Bearer ' + token() },
    });
    const body = await response.json();
    if (!response.ok) {
        const details = (body.errors ?? []).map((error) => error.detail).join(' | ');
        throw new Error('App Store Connect answered ' + response.status + ': ' + details);
    }
    return body;
}

const query = encodeURIComponent(bundleID);
const apps = await request('/v1/apps?filter[bundleId]=' + query + '&fields[apps]=name,bundleId,sku');
if (apps.data.length === 0) {
    console.error('FAIL  App Store Connect app record is absent.');
    console.error('Create Empires with bundle ID com.alexchandler.empires and SKU empires-ios, then rerun.');
    process.exit(2);
}
if (apps.data.length !== 1) {
    throw new Error('expected one Empires app record, found ' + apps.data.length);
}

const app = apps.data[0];
const profiles = await request(
    '/v1/profiles?filter[name]=Empires%20App%20Store'
        + '&fields[profiles]=name,profileState,profileType,expirationDate',
);
const profile = profiles.data.find((candidate) =>
    candidate.attributes.profileType === 'IOS_APP_STORE'
        && candidate.attributes.profileState === 'ACTIVE');
if (!profile) {
    console.error('FAIL  active IOS_APP_STORE profile named Empires App Store is absent.');
    process.exit(3);
}
console.log('PASS  distribution profile: ' + profile.attributes.name
    + ' (' + profile.id + ', expires ' + profile.attributes.expirationDate + ')');

const builds = await request(
    '/v1/builds?filter[app]=' + app.id + '&sort=-uploadedDate&limit=1'
        + '&fields[builds]=version,uploadedDate,processingState',
);
const latest = builds.data[0]?.attributes ?? null;
console.log('PASS  App Store Connect app: ' + app.attributes.name + ' (' + app.id + ')');
console.log(latest
    ? 'INFO  latest build: ' + latest.version + ', ' + latest.processingState
        + ', ' + latest.uploadedDate
    : 'INFO  no TestFlight builds uploaded yet');
