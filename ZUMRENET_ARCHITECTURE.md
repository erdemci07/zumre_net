“Bu belge ZümreNet geliştirmelerinde mimari referans olarak kullanılacaktır. Yeni bir özellik üzerinde çalışmadan önce bu belge ve özelliğin ilgili kaynak dosyaları birlikte okunmalıdır. Bu belge kaynak kodun yerine geçmez; çelişki halinde güncel kaynak kod esas alınır.”

# ZümreNet Mimari Referansı

Bu doküman mevcut kaynak kod okunarak hazırlanmıştır. Kodda görülmeyen özellikler var kabul edilmemiştir. Hedeflenen davranış ile mevcut kod davranışı ayrıştığında bu durum ayrıca belirtilmiştir.

## Teknoloji ve Mimari

ZümreNet bir Flutter uygulamasıdır. Firebase Authentication, Cloud Firestore, Cloud Functions, Firebase Hosting, Python/FastAPI tabanlı Cloud Run Smart Import servisi, Python/FastAPI tabanlı Cloud Run Reports servisi ve Flutter tarafında PDF byte paylaşımı için `printing` paketi kullanılır.

Uygulama giriş noktası `lib/main.dart` dosyasıdır. Firebase web yapılandırması burada yapılır. Web ortamında Auth persistence `Persistence.LOCAL` olarak ayarlanır. Giriş sonrası yönlendirme `FirebaseAuth.instance.authStateChanges()` ile başlar, ardından `users/{uid}` belgesindeki `role` alanı okunur.

Ana ekran dosyaları:

- `lib/screens/login_screen.dart`
- `lib/screens/student_home_screen.dart`
- `lib/screens/teacher_home_screen.dart`
- `lib/screens/study_guard_home_screen.dart`
- `lib/screens/admin_home_screen.dart`
- `lib/auth/auth_service.dart`
- `functions/index.js`
- `cloud_run_smart_import/main.py`
- `cloud_run_smart_import/smart_import_engine.py`

## Roller

Desteklenen temel roller:

- `student`
- `teacher`
- `studyGuard`
- `admin`

Rol yönlendirme `lib/main.dart` içinde yapılır:

- `teacher` -> `TeacherHomeScreen`
- `admin` -> `AdminHomeScreen`
- `studyGuard` -> `StudyGuardHomeScreen`
- Diğer veya eksik rol -> `StudentHomeScreen`

`AuthService.signIn` Firebase Auth ile giriş yapar, ardından `users/{uid}` belgesinin varlığını kontrol eder. Belge yoksa kullanıcı oturumdan çıkarılır.

## Roller ve Ekran Etkileşimleri

### Student

Öğrenci ekranı `users`, `queues` ve `settings/zumreSchedule` okur. Öğrenci sıra almak için `queues` koleksiyonuna belge ekler. Sıra iptalinde kendi queue belgesini `cancelled` yapar ve kendi `users/{uid}.cooldownUntil` alanını yazar. Soru tamamlanınca aktif queue state'i kapanır; güncel kodda öğrenci değerlendirme/rating yazımı yoktur.

Öğrenci ekranı aktif queue belgesini stream ile dinler. `waiting`, `in_progress`, `completed`, `cancelled` durumlarına göre arayüz değişir.

### Teacher

Öğretmen ekranı kendi `users/{uid}` belgesini, `settings/zumreSchedule` belgesini ve `queues` koleksiyonunu kullanır. Öğretmen `teacherStatus` ve `weeklyAvailability` günceller. Bekleyen ve aktif soruları `queues` üzerinden stream eder.

Öğretmen manuel öğrenci ekleyebilir, bekleyen sırayı başlatabilir, aktif soruyu tamamlayabilir, iptal edebilir veya başka öğretmene devredebilir.

### StudyGuard

Etüt görevlisi ekranı `settings/zumreSchedule`, `studySessions`, `studySessions/{sessionId}/students`, `users` ve `queues` kullanır. Etüt saatine göre aktif oturum açar veya kapatır. Öğrenciyi etüte alırken öğrencinin aktif queue içinde veya başka etütte olmamasını kontrol eder.

Görevli branş öğretmeni seçilirse seçilen öğretmenin mevcut `teacherStatus` değeri `dutyTeacherPreviousStatus` olarak saklanır ve öğretmen geçici olarak `studyGuard` yapılır.

### Admin

Admin ekranı istatistik, Rapor Merkezi, zaman yönetimi, Smart Import ve kullanıcı yönetimini içerir. Kullanıcı yönetiminde create/update/delete/password işlemleri server callable Cloud Functions üzerinden yürütülür; Firebase Authentication ve `users/{uid}` tek kullanıcı lifecycle olarak ele alınır.

## Firestore Veri Modeli

Bu model kodda görülen alanlara dayanır.

### `users/{uid}`

Ortak alanlar:

- `uid`: string
- `role`: string, `student`, `teacher`, `studyGuard`, `admin`
- `email`: string
- `username`: string
- `identityKey`: string
- `name`: string
- `surname`: string
- `fullName`: string
- `phone`: string, Smart Import tarafında yazılabilir
- `createdAt`: timestamp
- `updatedAt`: timestamp

Öğrenci alanları:

- `className`: string
- `branch`: string
- `department`: string
- `studentNo`: string
- `isInStudySession`: bool
- `activeStudySessionId`: string veya null
- `cooldownUntil`: timestamp

Öğretmen alanları:

- `subjects`: list veya eski verilerde string olabilir
- `branch`: string, bazı kod yollarında ilk ders/branş gibi kullanılır
- `subject`: string, legacy okuma desteği var
- `teacherStatus`: string
- `weeklyAvailability`: map; gün anahtarları altında `start`/`end` slot listeleri
- `manualAbsentDate`: string veya yok; Europe/Istanbul takvim günü için `YYYY-MM-DD` günlük "Kurumda Değilim" override değeri
- `breakUntil`: timestamp veya yok; süreli "Molada" durumunun bitiş zamanı

StudyGuard için kodda `role == studyGuard` temel alınır. `dutyTeacherId` ve `dutyTeacherName` alanları StudyGuard kullanıcısından okunuyor gibi görünür, ancak aktif akışta görevli öğretmen bilgisi `studySessions` üzerinde tutulur.

### `queues/{queueId}`

Kodda kullanılan alanlar:

- `studentId`: string
- `studentName`: string
- `teacherId`: string
- `teacherName`: string
- `subject`: string
- `status`: string
- `questionCount`: number
- `estimatedMinutes`: number
- `extraMinutes`: number
- `createdAt`: timestamp
- `startedAt`: timestamp veya null
- `completedAt`: timestamp
- `cancelledAt`: timestamp
- `updatedAt`: timestamp
- `isManual`: bool
- `autoCompleted`: bool, server timeout ile tamamlanan queue'larda yazılabilir
- `autoCompleteReason`: string, server timeout nedeni için yazılabilir
- `transferredAt`: timestamp
- `transferredFromTeacherId`: string
- `transferredFromTeacherName`: string

### `studySessions/{sessionId}`

Kodda kullanılan alanlar:

- `staffId`: string
- `staffName`: string
- `staffRole`: string
- `status`: string
- `startedAt`: timestamp
- `endedAt`: timestamp veya null
- `studentCount`: number
- `activeStudentCount`: number
- `dutyTeacherId`: string veya null
- `dutyTeacherName`: string veya null
- `dutyTeacherPreviousStatus`: string veya null
- `autoEnded`: bool
- `closedBy`: string, server scheduler tarafında `scheduledFunction`
- `closingStartedAt`: timestamp, Cloud Function geçici kapanış kilidi
- `lastCloseError`: string
- `createdAt`: timestamp
- `updatedAt`: timestamp

### `studySessions/{sessionId}/students/{studentId}`

Kodda kullanılan alanlar:

- `studentId`: string
- `studentName`: string
- `className`: string
- `branch`: string
- `department`: string
- `username`: string
- `checkedAt`: timestamp
- `checkedOutAt`: timestamp veya null
- `rejoinedAt`: timestamp
- `status`: string

### `settings/zumreSchedule`

Kodda kullanılan alanlar:

- `weekdaySlots`: list, hafta içi zümre saatleri
- `weekendSlots`: list, hafta sonu zümre saatleri
- `weekdayStudySlots`: list, hafta içi etüt saatleri
- `weekendStudySlots`: list, hafta sonu etüt saatleri
- `lunchBreak`: map, `start` ve `end`
- `updatedAt`: timestamp

Güncel kodda aktif rating/değerlendirme akışı yoktur. Eski queue belgelerinde `rating`, `comment`, `ratingPopupClosed` ve `ratedAt` alanları kalmış olabilir; bunlar geçmiş queue belgesini silmeden one-time cleanup ile temizlenebilir.

## Queue Durum Geçişleri

Kodda görülen queue status değerleri:

- `waiting`
- `in_progress`
- `completed`
- `cancelled`

Öğrenci sıra aldığında queue `waiting` olarak oluşturulur. Öğretmen bekleyen sırayı başlatınca `in_progress` olur. Öğretmen soruyu çözdü olarak işaretleyince `completed` olur. Öğrenci veya öğretmen iptal ederse `cancelled` olur.

Öğretmen başka bekleyen öğrenciyi sıra dışı başlatırken aktif soru varsa kullanıcıdan onay alınır; mevcut aktif soru batch içinde `completed`, yeni soru `in_progress` yapılır. Bu işlem batch kullanır ancak transaction kullanmaz.

Transfer akışında queue başka öğretmene atanır ve `status` tekrar `waiting` yapılır. Transfer alanları aynı belgeye yazılır.

Server zaman senkronizasyonunda zümre gerçekten kapalıysa `waiting` queue belgeleri silinir. `completed` queue geçmişi korunur. `in_progress` queue belgeleri zümre bitişinde silinmez veya hemen completed yapılmaz; zümre slot bitişinden 15 dakika sonra hâlâ `in_progress` ise server tarafından `completed` yapılabilir.

## TeacherStatus Değerleri

Güncel kodda kullanılan öğretmen durumları:

- `available`
- `break`
- `absent`
- `studyGuard`

Öğrenci ve transfer akışları yalnızca `teacherStatus == available` olan öğretmenleri uygun kabul eder. `break`, `absent` ve `studyGuard` yeni sıra için uygun değildir.

Öğretmen durum lifecycle hedefi:

- `teacherStatus == absent` tek başına manuel yokluk anlamına gelmez.
- `weeklyAvailability` varsayılan çalışma durumudur.
- `manualAbsentDate` bugünün Europe/Istanbul tarihi ise öğretmen o gün manuel olarak `absent` kalır.
- `breakUntil` gelecekteyse öğretmen süreli olarak `break` kalır.
- `studyGuard` etüt görevinde geçici durumdur ve sunucu zaman otomasyonu tarafından override edilmez.

Teacher ekranında "Kurumda Değilim" bugüne ait `manualAbsentDate` yazar. "Müsait" `manualAbsentDate` ve `breakUntil` alanlarını temizler, ardından durum mevcut `weeklyAvailability` ve saate göre yeniden hesaplanır. "Molada" 5/10/15 dakikalık `breakUntil` yazar ve ekrandaki sayaç local timer ile gösterilir. Çalışma programı kaydedildiğinde `studyGuard`, bugünkü manuel absent ve aktif break öncelikleri korunarak effective status anında yeniden hesaplanır. Server scheduler öğretmen cihazı kapalı olsa bile süresi dolan molaları ve program başlangıç/bitiş durumlarını `weeklyAvailability` üzerinden senkronize eder.

StudyGuard ekranında seçilen görevli branş öğretmeni geçici olarak `studyGuard` yapılır. Etüt bittiğinde veya görevli değiştiğinde öğretmen artık doğrudan eski `dutyTeacherPreviousStatus` değerine dönmez; bugünkü manuel yokluk ve o anki `weeklyAvailability` durumuna göre `available` veya `absent` olarak çözülür. `dutyTeacherPreviousStatus` geçmiş/fallback amaçlı tutulur.

Kod davranışı notu: `subjects` alanı Student, Teacher transfer ve StudyGuard öğretmen seçimi akışlarında hem `List` hem `String` olarak ele alınır. StudyGuard tarafında `branch` ve `subject` legacy alanları da hesaba katılır.

## Etüt Yaşam Döngüsü

StudyGuard ekranı etüt saatini `settings/zumreSchedule` üzerinden kontrol eder. Etüt saati açıksa aktif `studySessions` belgesi aranır, yoksa yeni oturum oluşturulur. Oturum `status: active` ile başlar.

Öğrenci etüte alınırken:

- Öğrencinin `isInStudySession == true` olmaması gerekir.
- Öğrencinin `queues` içinde `waiting` veya `in_progress` aktif kaydı olmaması gerekir.
- `studySessions/{sessionId}/students/{studentId}` belgesi yoksa oluşturulur.
- Aynı session içinde eski kayıt varsa ve `status != present` ise tekrar `present` yapılır.

Etütten çıkarma:

- Alt öğrenci kaydı `status: left` olur.
- `checkedOutAt` yazılır.
- Kullanıcıda `isInStudySession: false`, `activeStudySessionId: null` yazılır.
- `activeStudentCount` azaltılır.

Etüt kapatma:

- `present` öğrenciler `completed` yapılır.
- Öğrencilerin aktif etüt alanları temizlenir.
- Görevli öğretmen varsa güncel manuel yokluk ve çalışma programına göre `available` veya `absent` yapılır.
- Session `completed` yapılır.

## `studentCount` / `activeStudentCount` Farkı

Kodun hedeflediği anlam:

- `studentCount`: oturumdaki toplam/geçmiş katılım sayısıdır. Öğrenci ilk kez etüte alındığında artar. Öğrenci çıkarıldığında azalmaz.
- `activeStudentCount`: o anda etütte bulunan öğrenci sayısıdır. Öğrenci alınırken artar, çıkarılırken azalır, etüt kapanınca sıfırlanır.

Tekrar alma davranışı:

- Öğrenci aynı etüt içinde daha önce çıkarıldıysa alt kayıt silinmez.
- Aynı kayıt `present` yapılır.
- `activeStudentCount` artar.
- `studentCount` tekrar artmaz.

Kod davranışı notu: Çıkarma akışı transaction içinde güncel session/student belgesini okuyarak `activeStudentCount` değerini negatif olmayacak şekilde günceller.

## Zaman Yönetimi

Zaman konfigürasyonu `settings/zumreSchedule` belgesindedir.

Zümre saatleri:

- `weekdaySlots`
- `weekendSlots`

Etüt saatleri:

- `weekdayStudySlots`
- `weekendStudySlots`

Öğle arası:

- `lunchBreak.start`
- `lunchBreak.end`

Student, Teacher ve StudyGuard tarafında saat kontrolü genel olarak `start <= now < end` mantığıyla yapılır. Bu nedenle örneğin bitiş `20:30` ise `20:30` itibarıyla kapalı kabul edilmelidir.

Kod davranışı notu:

- StudyGuard ekranında `settings/zumreSchedule` stream ile belleğe alınır; local timer Firestore okumadan etüt saatini yeniden değerlendirir.
- Teacher ekranında aktif soru süresi için 1 saniyelik timer vardır. Zümre pill'i son 5 dakika metnini bellekteki slot bitişinden local timer ile günceller.
- Student ekranında cooldown için 1 saniyelik timer vardır.
- Student zümre saatini açılışta ve ilgili işlem öncesinde kontrol eder. Teacher ekranı zümre durumunu işlem öncesinde Firestore'dan doğrular; kompakt pill metni ise ek Firestore okuması yapmadan local timer ile güncellenir.

Cloud Function `syncStudySessions` her dakika çalışarak aktif etüt oturumlarını sunucu tarafında kapatır. Flutter timer arayüz ve istemci davranışı için, Cloud Function ise arka plan güvenlik ağı olarak konumlanmıştır.

Cloud Function `syncRuntimeSchedule` her dakika genel zümre/etüt runtime durumunu yazar. Aynı scheduler içinde zümre kapalıyken `waiting` queue belgeleri temizlenir ve zümre bitişinden 15 dakika sonra hâlâ `in_progress` kalan queue belgeleri `autoCompleted: true`, `autoCompleteReason: zumre_timeout` alanlarıyla completed yapılır.

## Smart Import Mimarisi

Güncel Smart Import hattı Flutter Admin ekranından Python/FastAPI Cloud Run servisine HTTP çağrıları ile çalışır.

Cloud Run base URL kodda:

`https://zumrenet-smart-import-542741706921.us-central1.run.app`

Endpointler:

- `POST /analyze`
- `POST /import`

`/analyze` Excel dosyasını base64 olarak alır, `smart_import_engine.py` ile header ve satır analizi yapar, `validRows`, `invalidPreview`, `mapping`, `warnings` ve confidence bilgileri döndürür.

`/import` geçerli satırları Firebase Admin SDK ile işler. Kullanıcı email ile varsa Auth şifresi güncellenir ve Firestore belgesi `merge=True` ile güncellenir. Kullanıcı yoksa Auth kullanıcısı ve Firestore belgesi oluşturulur.

Öğretmen import davranışı:

- Yeni öğretmende `teacherStatus: absent` ve `weeklyAvailability: {}` atanır.
- Mevcut öğretmende `teacherStatus` ve `weeklyAvailability` tekrar yazılmaz; bu, manuel durum/program ayarlarını korur.
- `subjects` güncellenir.

Eski Node import kodları `functions/services/*` altında durur. `functions/index.js` bunları require/export etmediği için mevcut Cloud Functions hattında kullanılmıyor gibi görünür.

## Cloud Functions / Cloud Run Görev Ayrımı

Cloud Functions:

- `adminCreateUser`: callable function. Admin doğrular, Firebase Auth kullanıcısı oluşturur, aynı uid ile `users/{uid}` belgesi oluşturur. Firestore create başarısız olursa Auth kullanıcısını silerek rollback dener.
- `adminUpdateUser`: callable function. Admin doğrular, profil alanlarını Firestore'da günceller, username/email değişmişse Firebase Auth email bilgisini de günceller.
- `adminDeleteUser`: callable function. Admin doğrular, self-delete ve aktif operasyon guard kontrollerinden sonra Firebase Auth hesabını ve `users/{uid}` belgesini siler. Auth `user-not-found` durumunda Firestore kaydını silerek legacy uyumsuzluğu reconcile edebilir.
- `updateUserPassword`: callable function. Çağıran kullanıcının `users/{uid}.role == admin` olmasını kontrol eder ve Firebase Auth şifresini günceller.
- `syncRuntimeSchedule`: scheduled function. Her dakika `settings/runtimeState` yazar, zümre kapalıyken stale `waiting` queue belgelerini siler ve 15 dakika timeout'a düşen `in_progress` queue belgelerini tamamlar.
- `syncStudySessions`: scheduled function. Her dakika `settings/zumreSchedule` okur, aktif `studySessions` belgelerini inceler, süresi biten etütleri kapatır.

Cloud Run:

- Smart Import analiz ve import işlerinden sorumludur.
- Reports servisi kurum/sınıf PDF raporlarını üretir.
- FastAPI ve Firebase Admin SDK kullanır.
- Flutter Admin ekranından doğrudan HTTP ile çağrılır.

Uygulama tarafı:

- Student/Teacher/StudyGuard ekranları canlı UI ve kullanıcı işlemlerinden sorumludur.
- Admin kullanıcı yönetimi Firebase Auth üzerinde doğrudan client işlemi yapmaz; callable function sonucu başarılı olmadan kullanıcı eklendi/güncellendi/silindi kabul edilmez.
- Sunucu scheduler etüt kapanışında güvenlik ağıdır.

## PDF Raporlama

Güncel hedef mimaride PDF raporlama Admin ekranında üretilmez. Admin ekranındaki Rapor Merkezi Firebase ID token ile `cloud_run_reports` FastAPI servisine HTTP çağrısı yapar ve dönen PDF byte'ını `Printing.sharePdf` ile kullanıcıya açar/paylaştırır.

Cloud Run Reports endpointleri:

- `POST /reports/institution-summary`: `KURUM FAALİYET ÖZETİ`
- `POST /reports/class-tracking`: `SINIF TAKİP RAPORU`
- `POST /reports/class-activity`: `SINIF FAALİYET TAKİP RAPORU`

Rapor auth davranışı:

- Eksik/geçersiz Authorization Bearer token `401` döndürür.
- Token geçerli olup `users/{uid}.role != admin` ise `403` döndürür.
- Token veya parola loglanmaz.

Zümre soru metriği kuralı: `queues` koleksiyonunda `status == completed` olan ve `completedAt` değeri rapor aralığına giren her belge 1 tamamlanan soru sayılır. `questionCount` üzerinden ortalama veya toplam üretilmez.

Etüt metriği kuralı: Yalnızca `studySessions.status == completed` oturumları rapora girer. Oturum süreleri mevcut `startedAt` ve `endedAt` alanlarından okunur; geçmiş raporlar güncel çalışma programına göre yeniden yorumlanmaz. Etüt öğrenci sayısı `studySessions/{sessionId}/students` kayıtlarındaki distinct öğrenci üzerinden gruplanır. Eski completed etütlerde `studentCount` negatif veya hatalı olabilir; rapor motoru bu alanı negatif göstermemeli ve gerçek katılım için öğrenci alt kayıtlarını esas almalıdır.

Performans notu: Rapor motoru Firestore verisini toplu sorgularla çeker ve Python içinde gruplar. Queue için `status + completedAt`, completed study session için `status + startedAt`, etüt öğrenci collection group sorgusu için `students.checkedAt` indeksleri `firestore.indexes.json` içinde tanımlıdır. Sınıf listesi `users.role == student` üzerinden alınır; sınıf raporu için `users.className` eşitlik filtresi kullanılır.

## Firestore Rules ve Index Durumu

Repo içinde `firestore.rules` ve `firestore.indexes.json` dosyaları bulunur. `firebase.json` Firestore rules ve indexes dosyalarını işaret eder.

Yeni geliştirmelerde her write işlemi için repo içindeki güncel rules dosyası ve deploy edilmiş Firebase rules davranışı birlikte kontrol edilmelidir. Raporlama servisi client rules'a değil Firebase Admin SDK yetkisine dayanır; bu nedenle servis içinde admin token doğrulaması zorunlu güvenlik sınırıdır.

## Teknik Borçlar

- Ekran dosyaları çok büyük ve sorumlulukları yoğun: Admin, Teacher, StudyGuard ve Student ekranları çok fazla iş mantığını doğrudan içeriyor.
- Firestore erişimleri UI dosyalarına dağılmış durumda; ortak repository/service katmanı yok.
- Eski Node import servisleri kullanım dışı gibi duruyor ama repo içinde hâlâ mevcut.
- `subjects`, `branch` ve legacy `subject` alanları birlikte kullanılıyor; veri uyumluluğu kod yoluna göre değişiyor.
- Timestamp yazımları bazı yerlerde `Timestamp.now()`, bazı yerlerde `FieldValue.serverTimestamp()` ile yapılıyor.
- Admin kullanıcı oluşturma client tarafında Identity Toolkit REST `accounts:signUp` ile yapılıyor; admin yetki modeli açısından Cloud Function tabanlı merkezi akış daha tutarlı olurdu.
- Firestore Rules ve index dosyalarının repoda olmaması geliştirme güvenliğini azaltıyor.
- Büyük koleksiyonlar bazı ekranlarda komple veya geniş şekilde okunuyor, sonra client tarafında filtreleniyor.

## Bilinen Riskler

- Duplicate queue riski: Öğrenci sıra alma ve öğretmen manuel öğrenci ekleme akışları read-then-add kullanıyor, transaction kullanmıyor.
- Aynı öğretmende birden fazla aktif soru riski: Başlatma akışında batch var ama transaction yok.
- Duplicate study session riski: Aktif session arama sonrası yeni session oluşturma transaction ile korunmuyor.
- `activeStudentCount` sapma riski: Eşzamanlı öğrenci çıkarma işlemlerinde önce oku sonra yaz deseni var.
- Teacher subject uyumsuzluğu: Bazı akışlar `subjects` string/list uyumlu, StudyGuard öğretmen seçimi sadece list bekliyor.
- Permission-denied riski: Rules dosyası repoda olmadığı için client write izinleri doğrulanamıyor.
- Index riski: Birden fazla `where` kullanılan sorgular için gerekli composite indexler repoda takip edilmiyor.
- PDF performans riski: Büyük raporlarda N+1 Firestore okuma maliyeti artabilir.
- Öğrenci cooldown temizleme client timer ile yapılıyor; kullanıcı ekranı açmazsa alan Firestore’da kalabilir, ancak karşılaştırma zaman bazlı yapıldığı için süresi geçmiş cooldown mantıken engel olmamalıdır.
- StudyGuard client kapanışı ile scheduled function aynı oturuma müdahale edebilir; Cloud Function tarafında claim mekanizması var, client tarafında aynı düzey transaction kilidi yok.

## Yeni Geliştirmelerde Uyulacak Kurallar

- Mevcut çalışan özelliği gereksiz yere yeniden yazma.
- Önce bu belgeyi, sonra ilgili kaynak dosyaları oku.
- Küçük değişiklikte küçük diff üret.
- Kullanılmayan eski mimariye geri dönme.
- `activeStudyDutyId` gibi kaldırılmış/eski alanları yeniden kullanma.
- `teacherStatus` değerlerini koru: `available`, `break`, `absent`, `studyGuard`.
- Etüt geçmiş verisini silme.
- Queue geçmiş verisini silme.
- Sunucu tarafı ve Flutter tarafı görevlerini birbirine karıştırma.
- Yeni alan eklemeden önce mevcut veri modelini kontrol et.
- Firestore Rules etkisini her write işleminde kontrol et.
- Bir özellik eklerken Student, Teacher, StudyGuard ve Admin tarafındaki etkisini düşün.
- Zaman kontrollerinde başlangıç dahil, bitiş hariç kullan: `start <= now < end`.
- Yoğun kullanımda race condition oluşturacak client-side read-then-write desenlerine dikkat et.
- Kullanıcı açıkça istemedikçe büyük refactor yapma.
- Kullanıcı açıkça istemedikçe dosya silme.
- Kod değişikliğinden önce hangi dosyalara dokunulacağını belirt.
- Kod değişikliğinden sonra değişen dosyaları, yapılan değişiklikleri, migration/rules/index ihtiyacını ve test edilmesi gereken senaryoları kısa şekilde raporla.

## Geliştirme Öncesi Kontrol Listesi

1. ZUMRENET_ARCHITECTURE.md okundu mu?
2. Değişecek ekran/dosyalar okundu mu?
3. Firestore read/write etkisi kontrol edildi mi?
4. Firestore Rules etkisi var mı?
5. Index gereksinimi var mı?
6. Student / Teacher / StudyGuard / Admin etkileri kontrol edildi mi?
7. Queue veya StudySession geçmiş verisi etkileniyor mu?
8. Race condition ihtimali var mı?
9. Mevcut status değerleri korunuyor mu?
10. Değişiklik mümkün olan en küçük diff ile yapılabilir mi?
11. Manuel test senaryoları belirlendi mi?
