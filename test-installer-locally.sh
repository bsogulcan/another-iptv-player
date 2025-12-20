#!/bin/bash
# Lokal test için GitHub Actions'ı tetikleme script'i
# Bu script GitHub Actions'ı manuel tetikler ve artifact'i indirir

echo "🚀 Windows Installer Lokal Test Script"
echo "========================================"
echo ""
echo "Bu script GitHub Actions'ı tetikleyip installer'ı test eder."
echo ""

# GitHub repo bilgilerini kontrol et
REPO_URL=$(git remote get-url origin 2>/dev/null | sed 's/\.git$//' | sed 's/.*github\.com[:/]//')
if [ -z "$REPO_URL" ]; then
    echo "❌ Hata: GitHub repo URL'i bulunamadı"
    exit 1
fi

echo "📦 Repo: $REPO_URL"
echo ""

# Kullanıcıya seçenekleri göster
echo "Seçenekler:"
echo "1) GitHub Actions'ı manuel tetikle (önerilen)"
echo "2) GitHub CLI ile otomatik tetikle (gh CLI gerekli)"
echo ""
read -p "Seçiminiz (1 veya 2): " choice

case $choice in
    1)
        echo ""
        echo "📋 Manuel tetikleme adımları:"
        echo "1. GitHub'da repo'nuzu açın: https://github.com/$REPO_URL"
        echo "2. 'Actions' sekmesine gidin"
        echo "3. Sol menüden 'Test Windows Installer' workflow'unu seçin"
        echo "4. Sağ üstteki 'Run workflow' butonuna tıklayın"
        echo "5. Branch'i seçin (main) ve 'Run workflow' butonuna tıklayın"
        echo "6. Build tamamlandığında (5-10 dakika) artifact'i indirin"
        echo ""
        echo "💡 İpucu: Build tamamlandığında workflow run sayfasında 'Artifacts' bölümünden"
        echo "   'windows-installer-test.zip' dosyasını indirebilirsiniz."
        ;;
    2)
        # GitHub CLI kontrolü
        if ! command -v gh &> /dev/null; then
            echo "❌ GitHub CLI (gh) kurulu değil"
            echo "   Kurulum: brew install gh"
            exit 1
        fi
        
        echo ""
        echo "🔄 GitHub Actions workflow'unu tetikliyorum..."
        gh workflow run "Test Windows Installer.yml" --ref main
        
        if [ $? -eq 0 ]; then
            echo "✅ Workflow başarıyla tetiklendi!"
            echo ""
            echo "⏳ Build'in tamamlanmasını bekleyin (5-10 dakika)..."
            echo ""
            echo "Build durumunu kontrol etmek için:"
            echo "  gh run list --workflow='Test Windows Installer.yml'"
            echo ""
            echo "Artifact'i indirmek için:"
            echo "  gh run download --workflow='Test Windows Installer.yml'"
        else
            echo "❌ Workflow tetiklenemedi"
            exit 1
        fi
        ;;
    *)
        echo "❌ Geçersiz seçim"
        exit 1
        ;;
esac

