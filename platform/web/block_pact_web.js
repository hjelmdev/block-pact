// Block Pact – browser helpers, injected at startup by the Platform autoload.
// Provides a mobile-friendly text input overlay: Godot's canvas text fields
// are awkward on phones (virtual keyboard, zoom, autocorrect), so on mobile
// the game asks this overlay instead. Styling lives here – edit freely.
(function () {
  if (window.blockPact) return;

  var css = `
  .bp-overlay{position:fixed;inset:0;z-index:9999;display:flex;align-items:flex-start;justify-content:center;
    background:rgba(5,7,14,.78);padding:max(12px,env(safe-area-inset-top)) 12px 12px;box-sizing:border-box;
    font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;}
  .bp-card{margin-top:12vh;width:100%;max-width:420px;background:#141a2a;border:1px solid #2c3550;border-radius:14px;
    padding:18px;box-shadow:0 10px 40px rgba(0,0,0,.5);color:#e8ecff;box-sizing:border-box;}
  .bp-title{font-size:17px;font-weight:600;margin:0 0 12px;}
  .bp-input{width:100%;box-sizing:border-box;font-size:18px;padding:12px 14px;border-radius:10px;border:2px solid #2f3a5c;
    background:#0b0f1a;color:#fff;outline:none;-webkit-appearance:none;}
  .bp-input:focus{border-color:#5bd8ff;}
  .bp-row{display:flex;gap:10px;margin-top:14px;}
  .bp-btn{flex:1;font-size:16px;padding:12px;border-radius:10px;border:0;cursor:pointer;font-weight:600;}
  .bp-ok{background:#5bd8ff;color:#06111c;} .bp-cancel{background:#262e45;color:#cfd6f3;}
  .bp-hint{font-size:12px;color:#8a93b5;margin-top:8px;}`;
  var style = document.createElement("style");
  style.textContent = css;
  document.head.appendChild(style);

  function isMobile() {
    return /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent) ||
      (navigator.maxTouchPoints > 1 && /Macintosh/.test(navigator.userAgent));
  }

  function promptText(title, value, maxLength, callback) {
    var overlay = document.createElement("div");
    overlay.className = "bp-overlay";
    overlay.innerHTML =
      '<div class="bp-card"><p class="bp-title"></p>' +
      '<input class="bp-input" type="text" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" enterkeyhint="done">' +
      '<div class="bp-hint"></div>' +
      '<div class="bp-row"><button class="bp-btn bp-cancel">Cancel</button><button class="bp-btn bp-ok">OK</button></div></div>';
    overlay.querySelector(".bp-title").textContent = title || "";
    var input = overlay.querySelector(".bp-input");
    input.value = value || "";
    if (maxLength > 0) {
      input.maxLength = maxLength;
      overlay.querySelector(".bp-hint").textContent = "Max " + maxLength + " characters";
    }
    var done = false;
    function finish(result) {
      if (done) return;
      done = true;
      overlay.remove();
      var canvas = document.querySelector("canvas");
      if (canvas) canvas.focus();
      callback(result);
    }
    overlay.querySelector(".bp-ok").onclick = function () { finish(input.value); };
    overlay.querySelector(".bp-cancel").onclick = function () { finish(null); };
    overlay.addEventListener("click", function (e) { if (e.target === overlay) finish(null); });
    input.addEventListener("keydown", function (e) {
      e.stopPropagation();
      if (e.key === "Enter") finish(input.value);
      if (e.key === "Escape") finish(null);
    });
    document.body.appendChild(overlay);
    setTimeout(function () { input.focus(); input.select(); }, 50);
  }

  window.blockPact = { isMobile: isMobile, promptText: promptText };
})();
