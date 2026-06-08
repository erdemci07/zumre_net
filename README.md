# ZümreNet

ZümreNet, dershaneler ve eğitim kurumları için geliştirilmiş gerçek zamanlı öğretmen–öğrenci soru yönetim sistemidir.

## Özellikler

### Öğrenci Paneli

* Ders seçerek sıra alma
* Öğretmen seçebilme veya rastgele öğretmene yönlendirilme
* Canlı sıra takibi
* Öğretmenin soru ile ilgilenmeye başladığını anlık görebilme
* Soru çözümü sonrası öğretmeni puanlama ve yorum yapma
* Sıra iptalinde bekleme süresi (cooldown) sistemi

### Öğretmen Paneli

* Bekleyen öğrencileri görüntüleme
* Öğrencileri manuel olarak kuyruğa ekleyebilme
* Soruları çözüldü olarak işaretleme
* Öğrenci değerlendirmelerini görüntüleme
* Müsait / Molada / Gelmedi durum yönetimi
* Günlük çözülen soru istatistikleri

### Yönetici Paneli

* Öğrenci ve öğretmen yönetimi
* Kullanıcı ekleme ve silme
* Son 7 günlük soru çözüm grafikleri
* Ders bazlı soru dağılımı
* Genel sistem istatistikleri

## Teknolojiler

* Flutter
* Firebase Authentication
* Cloud Firestore
* Provider

## Sistem Yapısı

ZümreNet üç farklı kullanıcı rolüne sahiptir:

1. Yönetici (Admin)
2. Öğretmen (Teacher)
3. Öğrenci (Student)

Her kullanıcı yalnızca kendi yetkileri dahilindeki ekranlara erişebilir.

## Amaç

ZümreNet'in amacı, dershane içerisindeki soru çözüm süreçlerini dijital ortama taşıyarak öğretmen ve öğrenciler arasındaki iletişimi hızlandırmak, bekleme sürelerini azaltmak ve kurum yönetimine detaylı istatistikler sunmaktır.

## Geliştirici

Faruk Erdemci

## Lisans

Bu proje özel kullanım amacıyla geliştirilmiştir.
