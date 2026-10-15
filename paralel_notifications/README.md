# Paralel Okuma – separate notifications service

- Project hosting the function: `zumrenet-657e1`
- Project containing reading data: `paralel-okuma`
- Function endpoint: `https://us-central1-zumrenet-657e1.cloudfunctions.net/paralelNotifications`
- Permissions: runtime identity `paralel-okuma-notifications@zumrenet-657e1.iam.gserviceaccount.com` needs Cloud Datastore Viewer in `paralel-okuma`, and Cloud Datastore User in `zumrenet-657e1` for deduplication.
- Create Google Secret Manager secrets **in zumrenet-657e1**, `PARALEL_PUSH_VAPID_PUBLIC` and `PARALEL_PUSH_VAPID_PRIVATE`, from a single `npx web-push generate-vapid-keys` output. Keep the private key secret.
- Grant the runtime identity Secret Manager Secret Accessor for **only these two secrets** if not automatically bound by Firebase.
- Deploy using GitHub Actions `Deploy Paralel Okuma Notifications` workflow_dispatch. Do not modify existing ZümreNet functions.
- Calling the HTTP endpoint requires a verified **Paralel Okuma Firebase Auth ID token**, a membership record and an actual newly-created matching `activities/{activityId}` record. The authenticated caller must be the movement's author.
- GET returns the VAPID public key for PushManager. POST body: `{"activityId":"..."}`, Authorization: Bearer Firebase ID token.
- Dispatch state is stored only in the ZümreNet collection `paralelNotificationDispatch`; all reading and push-subscription records remain in Paralel Okuma.
- Only works for clients using the new `web_push` device subscription scheme.
