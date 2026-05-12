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

/* ----- Optional: auto-resolve latest APK URL from GitHub releases -----
(async function resolveLatestApk() {
  const REPO = 'prakash66958-netizen/mnemo';
  try {
    const r = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`);
    if (!r.ok) return;
    const data = await r.json();
    const apk = data.assets?.find(a => a.name.endsWith('.apk'));
    if (!apk) return;
    document.querySelectorAll('a[href*="app-release.apk"]').forEach(a => {
      a.href = apk.browser_download_url;
    });
  } catch (e) {  }
})();
*/
