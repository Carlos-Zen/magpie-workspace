(() => {
  const base = window.location.pathname.endsWith('/')
    ? window.location.pathname
    : `${window.location.pathname}/`;
  const params = new URLSearchParams(window.location.hash.slice(1));
  params.set('autoconnect', 'true');
  params.set('resize', 'scale');
  params.set('path', `${base}websockify`);
  window.location.hash = params.toString();
})();
