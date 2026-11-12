// The hero mark moves into the toolbar once it scrolls out of view.
document.addEventListener('DOMContentLoaded', function () {
  var hero = document.querySelector('.mark-hero');
  if (!hero || !('IntersectionObserver' in window)) { document.body.classList.add('docked'); return; }
  new IntersectionObserver(function (e) {
    document.body.classList.toggle('docked', !e[0].isIntersecting);
  }).observe(hero);
});
