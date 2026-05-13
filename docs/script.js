/* ============================================
   MNEMO · landing page script
   ============================================ */

// Smooth-scroll offset for fixed nav (anchor links).
document.querySelectorAll('a[href^="#"]').forEach(link => {
  link.addEventListener('click', e => {
    const id = link.getAttribute('href');
    if (!id || id === '#') return;
    const target = document.querySelector(id);
    if (!target) return;
    e.preventDefault();
    const top = target.getBoundingClientRect().top + window.scrollY - 70;
    window.scrollTo({ top, behavior: 'smooth' });
  });
});

/* ----- Auto-resolve latest APK URL + version from GitHub releases ----- */
(async function resolveLatestRelease() {
  const REPO = 'prakash66958-netizen/mnemo';
  try {
    const r = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`);
    if (!r.ok) return;
    const data = await r.json();

    // Update all download links to point at the actual latest APK asset.
    const apk = data.assets?.find(a => a.name.endsWith('.apk'));
    if (apk) {
      document.querySelectorAll('a[href*="app-release.apk"]').forEach(a => {
        a.href = apk.browser_download_url;
      });
    }

    // Update version badges (elements with class "btn-ver") to show the
    // latest tag name (e.g. "v1.0.0" → "1.0.0").
    const version = (data.tag_name || '').replace(/^v/, '');
    if (version) {
      document.querySelectorAll('.btn-ver').forEach(el => {
        el.textContent = version;
      });
    }
  } catch (e) {
    // Silently fail — the hardcoded /releases/latest/download/ URL still
    // works as a fallback since GitHub redirects it to the actual asset.
  }
})();
