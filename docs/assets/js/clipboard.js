function copyText(btn, text) {
  navigator.clipboard.writeText(text).then(function() {
    var original = btn.textContent;
    btn.textContent = 'Copied!';
    btn.classList.add('copied');
    setTimeout(function() {
      btn.textContent = original;
      btn.classList.remove('copied');
    }, 2000);
  });
}
