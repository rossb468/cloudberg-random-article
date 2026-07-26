(function () {
  var articles = window.ARTICLES || [];
  var lastIndex = -1;

  var coverEl = document.getElementById('cover');
  var metaEl = document.getElementById('metaRow');
  var titleEl = document.getElementById('title');
  var subtitleEl = document.getElementById('subtitle');
  var readLinkEl = document.getElementById('readLink');
  var randomBtn = document.getElementById('randomBtn');
  var cardEl = document.getElementById('card');
  var counterEl = document.getElementById('counter');

  function pickIndex() {
    if (articles.length <= 1) return 0;
    var i;
    do {
      i = Math.floor(Math.random() * articles.length);
    } while (i === lastIndex);
    return i;
  }

  function formatDate(ts) {
    if (!ts) return '';
    var d = new Date(ts);
    return d.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
  }

  function imageUrl(imageId, width) {
    if (!imageId) return '';
    return 'https://miro.medium.com/v2/resize:fit:' + width + '/' + imageId;
  }

  function render(article) {
    if (article.image) {
      coverEl.classList.remove('placeholder');
      coverEl.src = imageUrl(article.image, 1200);
      coverEl.alt = article.title;
      coverEl.onerror = function () {
        coverEl.onerror = null;
        coverEl.removeAttribute('src');
        coverEl.classList.add('placeholder');
        coverEl.textContent = '✈️';
      };
    } else {
      coverEl.removeAttribute('src');
      coverEl.classList.add('placeholder');
      coverEl.textContent = '✈️';
    }

    metaEl.innerHTML = '';
    var meta = [formatDate(article.publishedAt), article.readingTime + ' min read'];
    meta.forEach(function (text) {
      if (!text) return;
      var span = document.createElement('span');
      span.textContent = text;
      metaEl.appendChild(span);
    });

    titleEl.textContent = article.title;
    subtitleEl.textContent = article.subtitle || '';
    readLinkEl.href = article.url;

    // restart entrance animation
    cardEl.style.animation = 'none';
    void cardEl.offsetWidth;
    cardEl.style.animation = '';
  }

  function showRandom() {
    var idx = pickIndex();
    lastIndex = idx;
    render(articles[idx]);
    counterEl.textContent = 'Article ' + (idx + 1) + ' of ' + articles.length + ' in the archive';
  }

  randomBtn.addEventListener('click', showRandom);

  if (articles.length === 0) {
    titleEl.textContent = 'No article data found';
    subtitleEl.textContent = 'data.js failed to load.';
  } else {
    showRandom();
  }
})();
