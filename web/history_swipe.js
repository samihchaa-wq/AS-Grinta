(function () {
  'use strict';

  // Flutter Web + WebKit can briefly expose the outgoing live canvas after
  // Safari has already revealed its cached history snapshot. That produces
  // the visible A -> B -> A -> B flash. On touch Apple browsers we prevent
  // the native edge-history gesture and perform the history move ourselves
  // once the swipe is completed, so there is only one navigation owner.
  var ua = navigator.userAgent || '';
  var platform = navigator.platform || '';
  var isIOS = /iPad|iPhone|iPod/.test(ua) ||
      (platform === 'MacIntel' && navigator.maxTouchPoints > 1);

  if (!isIOS || !('ontouchstart' in window)) return;

  var edgeWidth = 24;
  var triggerDistance = 64;
  var horizontalDominance = 1.25;
  var active = null;

  function reset() {
    active = null;
  }

  function pointFromTouch(touch) {
    return { x: touch.clientX, y: touch.clientY };
  }

  function onTouchStart(event) {
    if (event.touches.length !== 1) {
      reset();
      return;
    }

    var point = pointFromTouch(event.touches[0]);
    var width = window.innerWidth;
    var edge = null;

    if (point.x <= edgeWidth) {
      edge = 'left';
    } else if (point.x >= width - edgeWidth) {
      edge = 'right';
    } else {
      reset();
      return;
    }

    active = {
      edge: edge,
      startX: point.x,
      startY: point.y,
      lastX: point.x,
      lastY: point.y,
    };

    // Must be non-passive. Preventing the initial touch is what keeps WebKit
    // from starting its own interactive back/forward snapshot animation.
    event.preventDefault();
  }

  function onTouchMove(event) {
    if (!active || event.touches.length !== 1) return;
    var point = pointFromTouch(event.touches[0]);
    active.lastX = point.x;
    active.lastY = point.y;
    event.preventDefault();
  }

  function onTouchEnd(event) {
    if (!active) return;

    var gesture = active;
    reset();

    if (event.changedTouches && event.changedTouches.length) {
      var point = pointFromTouch(event.changedTouches[0]);
      gesture.lastX = point.x;
      gesture.lastY = point.y;
    }

    event.preventDefault();

    var dx = gesture.lastX - gesture.startX;
    var dy = gesture.lastY - gesture.startY;
    var absX = Math.abs(dx);
    var absY = Math.abs(dy);

    if (absX < triggerDistance) return;
    if (absX < absY * horizontalDominance) return;

    if (gesture.edge === 'left' && dx > 0) {
      window.history.back();
    } else if (gesture.edge === 'right' && dx < 0) {
      window.history.forward();
    }
  }

  function onTouchCancel(event) {
    if (active) event.preventDefault();
    reset();
  }

  var options = { capture: true, passive: false };
  document.addEventListener('touchstart', onTouchStart, options);
  document.addEventListener('touchmove', onTouchMove, options);
  document.addEventListener('touchend', onTouchEnd, options);
  document.addEventListener('touchcancel', onTouchCancel, options);
})();
