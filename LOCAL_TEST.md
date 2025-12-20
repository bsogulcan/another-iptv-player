# Lokal Test Rehberi (macOS)

macOS'ta NSIS çalışmadığı için installer'ı direkt lokal olarak oluşturamazsınız. Ancak birkaç yöntemle test edebilirsiniz:

## 🎯 Yöntem 1: GitHub Actions Manuel Tetikleme (En Kolay)

### Adımlar:

1. **GitHub'da repo'nuzu açın:**
   ```
   https://github.com/[kullanıcı-adı]/another-iptv-player
   ```

2. **Actions sekmesine gidin**

3. **Sol menüden "Test Windows Installer" workflow'unu seçin**

4. **Sağ üstteki "Run workflow" butonuna tıklayın**

5. **Branch'i seçin** (genellikle `main`) ve **"Run workflow"** butonuna tıklayın

6. **Build tamamlandığında** (5-10 dakika):
   - Workflow run sayfasında en altta **"Artifacts"** bölümünü göreceksiniz
   - `windows-installer-test.zip` dosyasını indirin
   - Windows'ta ZIP'i çıkarıp test edin

### Otomatik Script Kullanımı:

```bash
./test-installer-locally.sh
```

Script size adımları gösterecek.

## 🎯 Yöntem 2: GitHub CLI ile Otomatik Tetikleme

Eğer GitHub CLI kuruluysa:

```bash
# GitHub CLI kurulumu (eğer yoksa)
brew install gh

# GitHub'a login olun
gh auth login

# Workflow'u tetikleyin
gh workflow run "Test Windows Installer.yml" --ref main

# Build durumunu kontrol edin
gh run list --workflow="Test Windows Installer.yml"

# Artifact'i indirin (build tamamlandıktan sonra)
gh run download --workflow="Test Windows Installer.yml"
```

## 🎯 Yöntem 3: Windows VM veya Docker

Eğer Windows VM'iniz varsa veya Docker kullanabiliyorsanız:

### Windows VM'de:
1. NSIS'i kurun: https://nsis.sourceforge.io/Download
2. Flutter'ı kurun
3. Projeyi clone edin
4. `flutter build windows` çalıştırın
5. `cd windows && makensis installer.nsi` çalıştırın

### Docker ile (Gelişmiş):
Windows container kullanarak test edebilirsiniz, ancak bu daha karmaşık.

## ⚠️ Önemli Notlar

- **macOS'ta NSIS çalışmaz** - Windows gerekli
- **GitHub Actions en pratik çözüm** - Ücretsiz ve hızlı
- **Test workflow'u release oluşturmaz** - Sadece artifact oluşturur
- **Artifact 7 gün saklanır** - İndirmeyi unutmayın

## 📋 Test Checklist

Installer'ı test ederken kontrol edin:

- [ ] Installer başarıyla çalışıyor mu?
- [ ] Program Files'a doğru kuruluyor mu?
- [ ] Başlat menüsünde kısayol oluşuyor mu?
- [ ] Masaüstü kısayolu oluşuyor mu (seçildiyse)?
- [ ] Uygulama başarıyla çalışıyor mu?
- [ ] Windows "Programs and Features" listesinde görünüyor mu?
- [ ] Uninstaller çalışıyor mu?
- [ ] Kaldırma işlemi tüm dosyaları temizliyor mu?
- [ ] Kurulumdan sonra indirilen ZIP dosyası silinebiliyor mu?

