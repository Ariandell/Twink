// Switching screens must not carry a previous screen's scroll offset forward.
function installScrollReset() {
  let activeView = null;
  const views = [...document.querySelectorAll('.view-section')];
  const reset = () => {
    const next = views.find(view => view.getClientRects().length > 0);
    if (next && next !== activeView) {
      activeView = next;
      window.scrollTo({ top: 0, left: 0, behavior: 'instant' });
    }
  };
  const observer = new MutationObserver(reset);
  // Only screen visibility changes matter; timers, inputs and animation frames
  // do not reset the user's position while reading a screen.
  for (const view of views)
    observer.observe(view, { attributes: true, attributeFilter: ['class'] });
  const settings = document.getElementById('session-settings-menu');
  if (settings) {
    let wasOpen = false;
    new MutationObserver(() => {
      const open = !settings.classList.contains('hidden');
      if (open && !wasOpen) {
        const content = settings.querySelector('.card-edit-content');
        if (content) content.scrollTop = 0;
      }
      wasOpen = open;
    }).observe(settings, { attributes: true, attributeFilter: ['class'] });
  }
  reset();
}
if (document.readyState === 'loading')
  document.addEventListener('DOMContentLoaded', installScrollReset, { once: true });
else installScrollReset();
