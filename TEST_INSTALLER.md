# Windows Installer Test Rehberi

## Yöntem 1: GitHub Actions ile Test (Önerilen)

Bu en kolay ve güvenilir yöntemdir. GitHub Actions otomatik olarak installer'ı oluşturur.

### Adımlar:

1. **Değişiklikleri commit ve push edin:**
   ```bash
   git add .
   git commit -m "Add Windows installer support"
   git push origin main
   ```

2. **Yeni bir release tag'i oluşturun:**
   ```bash
   git tag v1.3.1
   git push origin v1.3.1
   ```

3. **GitHub Actions'ı kontrol edin:**
   - GitHub repo'nuzda "Actions" sekmesine gidin
   - "Create Release" workflow'unun çalıştığını göreceksiniz
   - Build tamamlandığında, "Releases" sayfasında installer dosyasını göreceksiniz

4. **Test edin:**
   - Release sayfasından `another-iptv-player-windows-setup-v1.3.1.zip` dosyasını indirin
   - ZIP'i çıkarın ve `another-iptv-player-windows-setup-v1.3.1.exe` dosyasını çalıştırın
   - Kurulum sihirbazını takip edin
   - Kurulumun başarılı olduğunu kontrol edin

## Yöntem 2: Lokal Windows'ta Test

Eğer Windows makineniz varsa, lokal olarak test edebilirsiniz.

### Gereksinimler:
- Windows 10/11
- NSIS (https://nsis.sourceforge.io/Download)
- Flutter SDK

### Adımlar:

1. **NSIS'i kurun:**
   - https://nsis.sourceforge.io/Download adresinden NSIS'i indirin
   - Kurulumu tamamlayın

2. **Flutter uygulamasını build edin:**
   ```bash
   flutter pub get
   flutter packages pub run build_runner build --delete-conflicting-outputs
   flutter build windows
   ```

3. **Installer'ı oluşturun:**
   ```bash
   cd windows
   makensis installer.nsi
   ```

4. **Installer'ı test edin:**
   - `another-iptv-player-windows-setup.exe` dosyası oluşturulacak
   - Bu dosyayı çalıştırarak kurulumu test edin
   - Program Files'a kurulduğunu kontrol edin
   - Başlat menüsünde kısayol olduğunu kontrol edin
   - Uninstaller'ın çalıştığını test edin

## Yöntem 3: GitHub Actions'da Manual Trigger

Eğer release tag'i oluşturmadan test etmek isterseniz:

1. GitHub repo'nuzda "Actions" sekmesine gidin
2. "Create Release" workflow'unu seçin
3. Sağ üstteki "Run workflow" butonuna tıklayın
4. Tag name olarak test tag'i girin (örn: `v1.3.1-test`)
5. "Run workflow" butonuna tıklayın

**Not:** Bu yöntem sadece workflow'u test eder, gerçek release oluşturmaz.

## Test Checklist

Kurulumu test ederken şunları kontrol edin:

- [ ] Installer başarıyla çalışıyor mu?
- [ ] Program Files'a doğru kuruluyor mu?
- [ ] Başlat menüsünde kısayol oluşuyor mu?
- [ ] Masaüstü kısayolu oluşuyor mu (seçildiyse)?
- [ ] Uygulama başarıyla çalışıyor mu?
- [ ] Windows "Programs and Features" listesinde görünüyor mu?
- [ ] Uninstaller çalışıyor mu?
- [ ] Kaldırma işlemi tüm dosyaları temizliyor mu?
- [ ] Kurulumdan sonra indirilen ZIP dosyası silinebiliyor mu?

