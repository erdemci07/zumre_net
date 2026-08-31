## ZümreNet

ZümreNet, dershaneler ve eğitim kurumları için geliştirilmiş gerçek zamanlı öğretmen–öğrenci soru ve etüt yönetim sistemidir.

## Amaç

ZümreNet'in amacı, dershane içerisindeki soru çözüm ve etüt süreçlerini dijital ortama taşıyarak öğretmen ve öğrenciler arasındaki iletişimi hızlandırmak, bekleme sürelerini azaltmak, öğretmenlerin iş yükünü dengeli dağıtmak ve kurum yönetimine detaylı istatistikler sunmaktır

## Özellikler

Öğretmen Paneli

* Haftalık çalışma programını ayarlayabilme
* Bekleyen öğrencileri görüntüleme
* Öğrencileri manuel olarak kuyruğa ekleyebilme
* Soruları çözüldü olarak işaretleme
* Müsait / Molada / Gelmedi durum yönetimi
* Günlük çözülen soru istatistikleri
* Etüt sürecindeki öğrenci ve soru takibi

Öğrenci Paneli

* Ders seçerek sıra alma
* Öğretmen seçebilme veya en uygun öğretmene otomatik yönlendirilme
* Öğretmenlerin müsaitlik ve yoğunluk durumuna göre akıllı yönlendirme
* Canlı sıra takibi
* Öğretmenin soru ile ilgilenmeye başladığını anlık görebilme
* Soru çözümü sonrası öğretmeni puanlama ve yorum yapma
* Sıra iptalinde bekleme süresi (cooldown) sistemi


Etüt Sistemi

* Kurum için etüt başlangıç ve bitiş saatleri belirleme
* Hafta içi ve hafta sonu için farklı etüt saatleri tanımlama
* Etüt süreçlerini otomatik olarak takip etme
* Etüt içerisindeki soru çözüm hareketlerini kayıt altına alma
* Etüt sonunda açık kalan süreçlerin kontrollü şekilde yönetilmesi

Akıllı Yönlendirme

* Öğrenciyi seçtiği derse uygun öğretmenlere yönlendirme
* Öğretmenin müsaitlik durumunu ve mevcut yoğunluğunu dikkate alma
* Öğretmenler arasındaki öğrenci dağılımını dengeleme
* Uygun öğretmeni otomatik belirleyerek bekleme süresini azaltma

Yönetici Paneli

* Öğrenci ve öğretmen yönetimi
* Kullanıcı ekleme, düzenleme ve silme
* Toplu kullanıcı yükleme
* Öğrenci sınıf ve öğretmen branş bilgilerinin yönetimi
* Etüt saatlerinin yönetimi
* Son 7 günlük soru çözüm grafikleri
* Ders bazlı soru dağılımı
* Öğretmen bazlı çözüm istatistikleri
* Genel sistem istatistikleri

Teknolojiler

* Flutter
* Firebase Authentication
* Cloud Firestore
* Provider

Sistem Yapısı

ZümreNet üç farklı kullanıcı rolüne sahiptir:

1. Yönetici (Admin)
2. Öğretmen (Teacher)
3. Öğrenci (Student)

Her kullanıcı yalnızca kendi yetkileri dahilindeki ekranlara erişebilir.

Soru sıraları ve öğretmen durumları gerçek zamanlı olarak güncellenir. Akıllı yönlendirme sistemi; öğretmenin branşını, müsaitlik durumunu ve mevcut yoğunluğunu dikkate alarak öğrenciyi uygun öğretmene yönlendirir.


## Geliştirici

Faruk Erdemci

Lisans

Bu proje özel kullanım amacıyla geliştirilmiştir.


Copyright © 2026 Faruk Erdemci

All Rights Reserved.

ZümreNet kaynak kodları, tasarımı, veri modeli ve tüm ilişkili bileşenler telif hakkı ile korunmaktadır.

Bu yazılımın veya herhangi bir bölümünün;

* Kopyalanması
* Değiştirilmesi
* Yeniden dağıtılması
* Ticari amaçla kullanılması
* Satılması
* Alt lisans verilmesi

hak sahibinin açık yazılı izni olmadan yasaktır.

Unauthorized copying, modification, redistribution, publication, sublicensing, or commercial use of this software is strictly prohibited.