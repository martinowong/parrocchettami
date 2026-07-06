const voiceWaveforms = Array.from(document.querySelectorAll(".voice-waveform-path"));

if (voiceWaveforms.length > 0) {
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const width = 760;
  const height = 170;
  const centerY = height / 2;
  const sampleCount = 92;
  let seed = 42;
  let lastFrame = performance.now();
  let energy = 0.18;
  let targetEnergy = 0.24;
  let frequencyBias = 1;
  let targetFrequencyBias = 1;
  let nextSpeechChange = 0;
  let nextOscillatorChange = 0;
  let nextNoiseChange = 0;
  let scroll = 0;
  let isSpeaking = false;

  const random = () => {
    seed = (seed * 1664525 + 1013904223) % 4294967296;
    return seed / 4294967296;
  };

  const randomBetween = (min, max) => min + random() * (max - min);
  const smoothStep = (value) => value * value * (3 - 2 * value);
  const interpolate = (current, target, deltaSeconds, response) => {
    return current + (target - current) * (1 - Math.exp(-deltaSeconds / response));
  };

  const oscillators = [
    { cycles: 1.35, targetCycles: 1.35, amp: 0.42, targetAmp: 0.42, phase: randomBetween(0, Math.PI * 2), speed: 0.24 },
    { cycles: 2.05, targetCycles: 2.05, amp: 0.31, targetAmp: 0.31, phase: randomBetween(0, Math.PI * 2), speed: 0.34 },
    { cycles: 3.2, targetCycles: 3.2, amp: 0.2, targetAmp: 0.2, phase: randomBetween(0, Math.PI * 2), speed: 0.52 },
    { cycles: 4.6, targetCycles: 4.6, amp: 0.1, targetAmp: 0.1, phase: randomBetween(0, Math.PI * 2), speed: 0.7 }
  ];

  const waveformLayers = voiceWaveforms.map((element, index) => ({
    element,
    ampScale: [0.62, 0.48, 1.16][index] ?? 0.6,
    yOffset: [-18, 16, 0][index] ?? 0,
    phaseOffset: [0.92, 2.05, 0][index] ?? 0,
    flowOffset: [0.08, -0.06, 0][index] ?? 0,
    noiseScale: [0.2, 0.14, 0.32][index] ?? 0.2
  }));

  const noiseNodes = Array.from({ length: 18 }, () => {
    const value = randomBetween(-0.18, 0.18);
    return { value, target: value };
  });

  const setSpeechTarget = (time) => {
    isSpeaking = !isSpeaking;

    if (isSpeaking) {
      targetEnergy = randomBetween(0.48, 0.86);
      targetFrequencyBias = randomBetween(0.98, 1.16);
      nextSpeechChange = time + randomBetween(280, 780);
    } else {
      targetEnergy = randomBetween(0.14, 0.28);
      targetFrequencyBias = randomBetween(0.88, 1);
      nextSpeechChange = time + randomBetween(260, 620);
    }
  };

  const updateOscillatorTargets = (time) => {
    if (time < nextOscillatorChange) return;

    oscillators.forEach((oscillator, index) => {
      const baseCycles = [1.35, 2.05, 3.2, 4.6][index];
      const baseAmp = [0.42, 0.31, 0.2, 0.1][index];
      oscillator.targetCycles = baseCycles * randomBetween(0.92, 1.08);
      oscillator.targetAmp = baseAmp * randomBetween(0.86, 1.14);
    });

    nextOscillatorChange = time + randomBetween(1300, 2400);
  };

  const updateNoise = (time, deltaSeconds) => {
    if (time > nextNoiseChange) {
      noiseNodes.forEach((node) => {
        node.target = randomBetween(-0.13, 0.13);
      });
      nextNoiseChange = time + randomBetween(760, 1300);
    }

    noiseNodes.forEach((node) => {
      node.value = interpolate(node.value, node.target, deltaSeconds, 0.72);
    });
  };

  const noiseAt = (position) => {
    const scaled = position * noiseNodes.length;
    const leftIndex = Math.floor(scaled) % noiseNodes.length;
    const rightIndex = (leftIndex + 1) % noiseNodes.length;
    const mix = smoothStep(scaled - Math.floor(scaled));

    return noiseNodes[leftIndex].value * (1 - mix) + noiseNodes[rightIndex].value * mix;
  };

  const splinePath = (points) => {
    let path = `M${points[0].x.toFixed(2)} ${points[0].y.toFixed(2)}`;

    for (let index = 1; index < points.length; index += 1) {
      const previous = points[index - 1];
      const current = points[index];
      const midX = (previous.x + current.x) / 2;
      path += ` C${midX.toFixed(2)} ${previous.y.toFixed(2)}, ${midX.toFixed(2)} ${current.y.toFixed(2)}, ${current.x.toFixed(2)} ${current.y.toFixed(2)}`;
    }

    return path;
  };

  const drawWaveform = (time) => {
    const deltaSeconds = Math.min((time - lastFrame) / 1000, 0.05);
    lastFrame = time;

    if (time > nextSpeechChange) {
      setSpeechTarget(time);
    }

    updateOscillatorTargets(time);
    updateNoise(time, deltaSeconds);

    energy = interpolate(energy, targetEnergy, deltaSeconds, isSpeaking ? 0.2 : 0.32);
    frequencyBias = interpolate(frequencyBias, targetFrequencyBias, deltaSeconds, 0.62);
    scroll += deltaSeconds * (0.16 + energy * 0.34);

    oscillators.forEach((oscillator) => {
      oscillator.cycles = interpolate(oscillator.cycles, oscillator.targetCycles, deltaSeconds, 1.6);
      oscillator.amp = interpolate(oscillator.amp, oscillator.targetAmp, deltaSeconds, 1);
      oscillator.phase += deltaSeconds * oscillator.speed * frequencyBias * Math.PI * 2;
    });

    const createPoints = (layer) => Array.from({ length: sampleCount }, (_, index) => {
      const progress = index / (sampleCount - 1);
      const x = progress * width;
      const flowPosition = progress + scroll + layer.flowOffset;
      const edgeFade = Math.sin(progress * Math.PI) ** 0.72;
      const idleBreath = 0.78 + Math.sin(time * 0.00105 + layer.phaseOffset) * 0.1;
      const amplitude = (8 + energy * 44) * idleBreath * edgeFade * layer.ampScale;

      const oscillatorSignal = oscillators.reduce((sum, oscillator, oscillatorIndex) => {
        const phaseOffset = oscillatorIndex * 0.73 + layer.phaseOffset;
        return sum + Math.sin(flowPosition * Math.PI * 2 * oscillator.cycles + oscillator.phase + phaseOffset) * oscillator.amp;
      }, 0);

      const perturbation =
        Math.sin(flowPosition * Math.PI * 2 * 6.4 + time * 0.0013 + layer.phaseOffset) * 0.025 +
        noiseAt(flowPosition * 0.62 + layer.phaseOffset * 0.08) * layer.noiseScale;

      const y = centerY + layer.yOffset + (oscillatorSignal + perturbation) * amplitude;

      return {
        x,
        y: Math.max(18, Math.min(height - 18, y))
      };
    });

    waveformLayers.forEach((layer) => {
      layer.element.setAttribute("d", splinePath(createPoints(layer)));
    });

    if (!reducedMotion) {
      requestAnimationFrame(drawWaveform);
    }
  };

  setSpeechTarget(performance.now());
  drawWaveform(performance.now());
}

const formatCards = document.querySelectorAll(".format-card");

formatCards.forEach((card) => {
  card.addEventListener("mouseenter", () => {
    formatCards.forEach((item) => item.classList.remove("active"));
    card.classList.add("active");
  });
});

const languageOrbit = document.querySelector(".language-orbit");
const flagRing = document.querySelector(".flag-ring");

if (languageOrbit && flagRing) {
  const flagItems = Array.from(flagRing.querySelectorAll("span"));
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const normalVelocity = reducedMotion ? 0 : 10;
  const returnStrength = 0.85;
  let orbitAngle = 0;
  let velocity = normalVelocity;
  let lastFrame = performance.now();
  let isDragging = false;
  let lastPointerAngle = 0;
  let lastPointerTime = 0;

  const normalizeDelta = (delta) => {
    if (delta > 180) return delta - 360;
    if (delta < -180) return delta + 360;
    return delta;
  };

  const clampVelocity = (value) => Math.max(Math.min(value, 240), -240);

  const pointerMetrics = (event) => {
    const box = languageOrbit.getBoundingClientRect();
    const centerX = box.left + box.width / 2;
    const centerY = box.top + box.height / 2;
    const deltaX = event.clientX - centerX;
    const deltaY = event.clientY - centerY;

    return {
      angle: Math.atan2(deltaY, deltaX) * 180 / Math.PI,
      distance: Math.hypot(deltaX, deltaY)
    };
  };

  const orbitRadius = () => {
    const value = getComputedStyle(languageOrbit).getPropertyValue("--orbit-radius");
    return Number.parseFloat(value) || 176;
  };

  const isOnFlagRing = (event) => {
    const radius = orbitRadius();
    const band = Math.max(34, radius * 0.16);
    const { distance } = pointerMetrics(event);

    return distance >= radius - band && distance <= radius + band;
  };

  const pointerAngle = (event) => {
    return pointerMetrics(event).angle;
  };

  const nearestFlagIndex = (event) => {
    const step = 360 / flagItems.length;
    const angle = pointerAngle(event);
    const relativeAngle = ((angle - orbitAngle) % 360 + 360) % 360;

    return Math.round(relativeAngle / step) % flagItems.length;
  };

  const setOrbitAngle = () => {
    languageOrbit.style.setProperty("--orbit-angle", `${orbitAngle}deg`);
  };

  const clearFlagFocus = () => {
    flagItems.forEach((flag) => {
      flag.classList.remove("is-hovered", "is-neighbor", "is-near");
    });
  };

  const setFlagFocus = (activeIndex) => {
    const count = flagItems.length;

    flagItems.forEach((flag, index) => {
      const distance = Math.min(
        Math.abs(index - activeIndex),
        count - Math.abs(index - activeIndex)
      );

      flag.classList.toggle("is-hovered", distance === 0);
      flag.classList.toggle("is-neighbor", distance === 1);
      flag.classList.toggle("is-near", distance === 2);
    });
  };

  const animateOrbit = (time) => {
    const deltaSeconds = Math.min((time - lastFrame) / 1000, 0.05);
    lastFrame = time;

    if (!isDragging) {
      orbitAngle += velocity * deltaSeconds;
      velocity += (normalVelocity - velocity) * Math.min(deltaSeconds * returnStrength, 1);
      setOrbitAngle();
    }

    requestAnimationFrame(animateOrbit);
  };

  flagItems.forEach((flag, index) => {
    flag.addEventListener("focus", () => setFlagFocus(index));
    flag.addEventListener("blur", clearFlagFocus);
  });

  flagRing.addEventListener("pointerleave", () => {
    if (!isDragging) {
      flagRing.classList.remove("can-drag");
      clearFlagFocus();
    }
  });

  flagRing.addEventListener("pointerdown", (event) => {
    if (!isOnFlagRing(event)) return;

    event.preventDefault();
    isDragging = true;
    setFlagFocus(nearestFlagIndex(event));
    lastPointerAngle = pointerAngle(event);
    lastPointerTime = performance.now();
    velocity = 0;
    flagRing.classList.add("is-dragging");
    flagRing.setPointerCapture(event.pointerId);
  });

  flagRing.addEventListener("pointermove", (event) => {
    if (!isDragging) {
      const canDrag = isOnFlagRing(event);
      flagRing.classList.toggle("can-drag", canDrag);

      if (canDrag) {
        setFlagFocus(nearestFlagIndex(event));
      } else {
        clearFlagFocus();
      }

      return;
    }

    const currentAngle = pointerAngle(event);
    const currentTime = performance.now();
    const angleDelta = normalizeDelta(currentAngle - lastPointerAngle);
    const timeDelta = Math.max((currentTime - lastPointerTime) / 1000, 0.016);

    orbitAngle += angleDelta;
    velocity = clampVelocity(angleDelta / timeDelta);
    lastPointerAngle = currentAngle;
    lastPointerTime = currentTime;
    setOrbitAngle();
    setFlagFocus(nearestFlagIndex(event));
  });

  const endDrag = (event) => {
    if (!isDragging) return;
    isDragging = false;
    flagRing.classList.remove("is-dragging");

    if (flagRing.hasPointerCapture(event.pointerId)) {
      flagRing.releasePointerCapture(event.pointerId);
    }
  };

  flagRing.addEventListener("pointerup", endDrag);
  flagRing.addEventListener("pointercancel", endDrag);
  flagRing.addEventListener("lostpointercapture", () => {
    isDragging = false;
    flagRing.classList.remove("is-dragging");
  });

  requestAnimationFrame(animateOrbit);
}
