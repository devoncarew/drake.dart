
if (navigator.webkitStartDart) {
  navigator.webkitStartDart();
} else {
  var script = document.createElement('script');
  script.src = 'drake.dart.precompiled.js';
  document.body.appendChild(script);
}
