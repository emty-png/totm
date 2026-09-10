import QtQuick

// Easing table for animation sampling: named easings plus custom
// cubic-bezier. Cubics match CSS ease-in/out/in-out; slowDown is
// bezier(0.22, 1, 0.36, 1). The solver is Newton plus a bisection
// fallback. Progress is 0-1, matching the C++ video renderer
// (AnimSampler), which ports this file.
QtObject {
    id: easing

    // Easing ids: linear | easeIn | easeOut | easeInOut | slowDown |
    // custom (cubic-bezier [x1, y1, x2, y2]).
    function easeValue(id, bezier, t) {
        var x = Math.min(1, Math.max(0, t));
        if (id === "linear")
            return x;
        if (id === "easeIn")
            return x * x * x;
        if (id === "easeOut") {
            var u = 1 - x;
            return 1 - u * u * u;
        }
        if (id === "easeInOut")
            return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
        if (id === "custom") {
            var b = bezier || [0.25, 0.1, 0.25, 1];
            return easing.cubicBezier(b[0], b[1], b[2], b[3], x);
        }
        if (id === "slowDown")
            return easing.cubicBezier(0.22, 1, 0.36, 1, x);
        return x;
    }

    function cubicBezier(x1, y1, x2, y2, x) {
        if (x <= 0)
            return 0;
        if (x >= 1)
            return 1;
        var s = x, converged = false;
        for (var i = 0; i < 8; i++) {
            var u = 1 - s;
            var xs = 3 * u * u * s * x1 + 3 * u * s * s * x2 + s * s * s;
            var dx = 3 * u * u * x1 + 6 * u * s * (x2 - x1) + 3 * s * s * (1 - x2);
            if (Math.abs(xs - x) < 1e-6) {
                converged = true;
                break;
            }
            if (Math.abs(dx) < 1e-6 || (s = s - (xs - x) / dx) < 0 || s > 1)
                break;
        }
        if (!converged) {
            var lo = 0, hi = 1;
            s = Math.min(1, Math.max(0, s));
            for (var j = 0; j < 24; j++) {
                var v = 1 - s;
                var xsv = 3 * v * v * s * x1 + 3 * v * s * s * x2 + s * s * s;
                if (Math.abs(xsv - x) < 1e-6)
                    break;
                if (xsv < x)
                    lo = s;
                else
                    hi = s;
                s = (lo + hi) / 2;
            }
        }
        var w = 1 - s;
        return 3 * w * w * s * y1 + 3 * w * s * s * y2 + s * s * s;
    }
}
