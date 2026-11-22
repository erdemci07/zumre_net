# Ayet Rehberi Web Push — ZümreNet projesinde ayrı servis

- **Cloud/GCP project**: `zumrenet-657e1`, billing ve Cloud Scheduler burada çalışır.
- **Firebase Hosting / PWA**: `ayet-rehberi` projesinde kalır. Bu repoda Ayet UI deploy edilmez.
- **Cloud Functions codebase**: `ayet-notifications`, `firebase.ayet-notifications.json`
- **Functions**: `ayetPushApi` (HTTPS) ve `dispatchAyetReminders` (her 15 dakika).
- **API URL**: `https://us-central1-zumrenet-657e1.cloudfunctions.net/ayetPushApi`
- **Datastore**: yalnızca ZümreNet'in varsayılan Firestore veritabanı.
  `ayetPushDevices`, `ayetPushDispatch` ve `ayetPushRegistrationLimits`
  koleksiyonları. Paralel Okuma ve ZümreNet'in mevcut dokümanlarına dokunulmaz.
- **Runtime identity**: `ayet-rehberi-notifications@zumrenet-657e1.iam.gserviceaccount.com`
- **Secrets**: `AYET_PUSH_VAPID_PUBLIC` ve `AYET_PUSH_VAPID_PRIVATE`, ZümreNet projesinde.
  Paralel Okuma anahtarlarını **kullanma/değiştirme**.
- **Deployment**: `Deploy Ayet Rehberi Notifications` GitHub Actions.
  İlk başta yalnızca verify çalışır. Cloud hazırsa ZümreNet repo variable
  `ENABLE_AYET_NOTIFICATIONS_DEPLOY=true` yapıldıktan sonra `workflow_dispatch`
  ile fonksiyonları ayrı dağıt.
- **Deployment safety**: `firebase.json`, `functions/`, `paralel_notifications/`,
  `firestore.rules` veya ZümreNet hosting düzenlemesi yapılmaz.
  Deploy `--config firebase.ayet-notifications.json --only functions:ayet-notifications`.
- **Consent**: izin verilmeyen cihaz kaydedilmez; tüm ruh hâli geçmişi,
  favori ayetler ve ayet metinleri Ayet Rehberi cihazında kalır.
  Sunucuya cihazın Web Push aboneliği, son okuma/ziyaret özeti ve saat tercihleri gelir.
- **Public API security note**: Ayet Rehberi hesap açmadan çalışır. API
  cihaz-başına gizli anahtar ve yeni kayıtlar için IP/gün sınırı uygular.
  `Origin` kontrolü yalnızca tarayıcı korumasıdır, gerçek authentication değildir.
  Geniş ölçekli üretim kullanımı öncesinde anonim Firebase Auth + App Check
  önerilir; genel erişimli Endpoint'i maliyet ve anomali loglarıyla izleyin.

## GCloud: kullanıcı hesabı ile yalnızca ilk kurulum

```bash
gcloud config set project zumrenet-657e1
gcloud services enable cloudfunctions.googleapis.com cloudbuild.googleapis.com \
  run.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com \
  cloudscheduler.googleapis.com firestore.googleapis.com

gcloud iam service-accounts create ayet-rehberi-notifications \
  --display-name="Ayet Rehberi push runtime" --project=zumrenet-657e1

gcloud projects add-iam-policy-binding zumrenet-657e1 \
  --member="serviceAccount:ayet-rehberi-notifications@zumrenet-657e1.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

gcloud iam service-accounts add-iam-policy-binding \
  ayet-rehberi-notifications@zumrenet-657e1.iam.gserviceaccount.com \
  --member="serviceAccount:github-actions-hosting@zumrenet-657e1.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser" --project=zumrenet-657e1
```

Önceden oluşturulmuş bir runtime SA varsa yeniden oluşturmayın. GitHub WIF
servis hesabının Functions deploy yetkileri, Google Cloud build ve Cloud Scheduler
yetkileri de olmalı; Paralel Okuma workflow'u bunu kısmen doğrular fakat yeni SA
için `iam.serviceAccountUser` yine gerekir.

Tek bir VAPID çifti üret:

```bash
npx --yes web-push generate-vapid-keys
```

Public ve private key'i **sohbete / GitHub'a koyma**.
Aşağıdaki komutlarda terminalde elle gerçek değerlerle değiştir:

```bash
printf %s '<PUBLIC_KEY>' | gcloud secrets create AYET_PUSH_VAPID_PUBLIC \
  --project=zumrenet-657e1 --data-file=- --replication-policy=automatic
printf %s '<PRIVATE_KEY>' | gcloud secrets create AYET_PUSH_VAPID_PRIVATE \
  --project=zumrenet-657e1 --data-file=- --replication-policy=automatic
```

Secret önceden varsa `secrets versions add` kullan; yanlışlıkla farklı anahtar
çiftini karıştırma. Runtime identity'ye yalnızca bu iki Secret için
`roles/secretmanager.secretAccessor` ver (Console → Secret Manager → ilgili
Secret → Permissions).

**GitHub repository variable** (ZümreNet repo, Ayet repo değil):
`ENABLE_AYET_NOTIFICATIONS_DEPLOY=true` değerini ancak ayarlar tamamlanınca
ver. `Deploy Ayet Rehberi Notifications` workflow'unu elle tetikle. 2nd-gen
scheduler ilk dağıtımda Cloud Scheduler job oluşturacaktır.

Kontrol:
```bash
curl -sS https://us-central1-zumrenet-657e1.cloudfunctions.net/ayetPushApi
```

Yanıtta `vapidPublicKey` bulunmalı. iOS 16.4+ ana ekrana eklenmiş PWA'da
`Bende → Hatırlatmalar → Bildirimleri etkinleştir`, ardından `Sunucudan deneme gönder`.
Kilit ekranında gerçek teslimatı ayrıca sınayın.

Firestore TTL politikası `ayetPushRegistrationLimits.expireAt` için açılabilir;
açılmazsa eski hız-sınırı belgeleri zamanla birikir. `ayetPushDispatch` kayıtları
için de saklama süresi ve silme politikası tanımlayın.

Önemli: Bu repo ZümreNet'in Google Cloud kaynağıdır; Ayet Rehberi'nin web
arayüzü Ayet reposundaki bağımsız PR üzerinden dağıtılır.
