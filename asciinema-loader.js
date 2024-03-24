const presenterMode = window.location.hostname == "localhost";

document.addEventListener("DOMContentLoaded", function () {
  [...document.querySelectorAll(".asciinema")].forEach(function (el) {
    const player = AsciinemaPlayer.create(el.dataset.url, el, {
      controls: !presenterMode,
      autoPlay: presenterMode,
      pauseOnMarkers: presenterMode,
      fit: false,
      terminalFontSize: "12px",
      idleTimeLimit: 1,
      speed: 1.3,
      poster: "npt:0:00",
    });
    el.ap = player;
  });
});

if (presenterMode) {
  document.addEventListener("keypress", function (e) {
    if (e.key === "Enter") {
      const ap = document.querySelector(".bespoke-marp-active .ap-wrapper")
        ?.parentElement?.ap;
      if (ap) {
        if (ap.getCurrentTime() != ap.getDuration()) {
          ap.el.querySelector(".ap-player").focus();
          ap.play();
        }
      }
    }
  });
}
