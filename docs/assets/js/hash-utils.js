function parseHash() {
  var hash = location.hash.slice(1);
  if (!hash) return {};
  var result = {};
  hash.split('&').forEach(function(part) {
    var idx = part.indexOf('=');
    if (idx === -1) return;
    result[part.slice(0, idx)] = decodeURIComponent(part.slice(idx + 1));
  });
  return result;
}
