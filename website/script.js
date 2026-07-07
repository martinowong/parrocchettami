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
  let syllablePhase = 0;

  const random = () => {
    seed = (seed * 1664525 + 1013904223) % 4294967296;
    return seed / 4294967296;
  };

  const randomBetween = (min, max) => min + random() * (max - min);
  const smoothStep = (value) => value * value * (3 - 2 * value);
  const interpolate = (current, target, deltaSeconds, response) => {
    return current + (target - current) * (1 - Math.exp(-deltaSeconds / response));
  };

  syllablePhase = randomBetween(0, Math.PI * 2);

  const oscillators = [
    { cycles: 1.75, targetCycles: 1.75, amp: 0.36, targetAmp: 0.36, phase: randomBetween(0, Math.PI * 2), speed: 0.36 },
    { cycles: 3.2, targetCycles: 3.2, amp: 0.32, targetAmp: 0.32, phase: randomBetween(0, Math.PI * 2), speed: 0.62 },
    { cycles: 6.4, targetCycles: 6.4, amp: 0.2, targetAmp: 0.2, phase: randomBetween(0, Math.PI * 2), speed: 1.12 },
    { cycles: 9.4, targetCycles: 9.4, amp: 0.1, targetAmp: 0.1, phase: randomBetween(0, Math.PI * 2), speed: 1.28 },
    { cycles: 12.8, targetCycles: 12.8, amp: 0.045, targetAmp: 0.045, phase: randomBetween(0, Math.PI * 2), speed: 1.55 }
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
      targetEnergy = randomBetween(0.74, 1.08);
      targetFrequencyBias = randomBetween(1.14, 1.38);
      nextSpeechChange = time + randomBetween(280, 720);
    } else {
      targetEnergy = randomBetween(0.06, 0.2);
      targetFrequencyBias = randomBetween(0.86, 1.04);
      nextSpeechChange = time + randomBetween(160, 380);
    }
  };

  const primeSpeech = (time) => {
    isSpeaking = true;
    energy = randomBetween(0.72, 0.96);
    targetEnergy = randomBetween(0.86, 1.12);
    frequencyBias = randomBetween(1.14, 1.32);
    targetFrequencyBias = randomBetween(1.18, 1.42);
    nextSpeechChange = time + randomBetween(340, 760);
    scroll = randomBetween(0.12, 0.82);
    syllablePhase = randomBetween(0, Math.PI * 2);
  };

  const updateOscillatorTargets = (time) => {
    if (time < nextOscillatorChange) return;

    oscillators.forEach((oscillator, index) => {
      const baseCycles = [1.75, 3.2, 6.4, 9.4, 12.8][index];
      const baseAmp = [0.36, 0.32, 0.2, 0.1, 0.045][index];
      oscillator.targetCycles = baseCycles * randomBetween(0.9, 1.12);
      oscillator.targetAmp = baseAmp * randomBetween(0.82, 1.24);
    });

    nextOscillatorChange = time + randomBetween(760, 1400);
  };

  const updateNoise = (time, deltaSeconds) => {
    if (time > nextNoiseChange) {
      noiseNodes.forEach((node) => {
        node.target = randomBetween(-0.2, 0.2);
      });
      nextNoiseChange = time + randomBetween(340, 720);
    }

    noiseNodes.forEach((node) => {
      node.value = interpolate(node.value, node.target, deltaSeconds, 0.42);
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

    energy = interpolate(energy, targetEnergy, deltaSeconds, isSpeaking ? 0.2 : 0.3);
    frequencyBias = interpolate(frequencyBias, targetFrequencyBias, deltaSeconds, 0.46);
    scroll += deltaSeconds * (0.22 + energy * 0.48);
    syllablePhase += deltaSeconds * (isSpeaking ? 5.6 : 2.4);

    oscillators.forEach((oscillator) => {
      oscillator.cycles = interpolate(oscillator.cycles, oscillator.targetCycles, deltaSeconds, 0.72);
      oscillator.amp = interpolate(oscillator.amp, oscillator.targetAmp, deltaSeconds, 0.46);
      oscillator.phase += deltaSeconds * oscillator.speed * frequencyBias * Math.PI * 2;
    });

    const createPoints = (layer) => Array.from({ length: sampleCount }, (_, index) => {
      const progress = index / (sampleCount - 1);
      const x = progress * width;
      const flowPosition = progress + scroll + layer.flowOffset;
      const edgeFade = Math.sin(progress * Math.PI) ** 0.72;
      const idleBreath = 0.78 + Math.sin(time * 0.00105 + layer.phaseOffset) * 0.1;
      const syllable =
        0.58 +
        Math.max(0, Math.sin(flowPosition * Math.PI * 2 * 3.35 - syllablePhase + layer.phaseOffset)) ** 2.15 * 0.58;
      const plosive =
        Math.max(0, Math.sin(flowPosition * Math.PI * 2 * 6.4 + syllablePhase * 0.95 + layer.phaseOffset)) ** 5.4 *
        energy *
        0.26;
      const amplitude = (6 + energy * 58) * idleBreath * edgeFade * (syllable + plosive) * layer.ampScale;

      const oscillatorSignal = oscillators.reduce((sum, oscillator, oscillatorIndex) => {
        const phaseOffset = oscillatorIndex * 0.73 + layer.phaseOffset;
        return sum + Math.sin(flowPosition * Math.PI * 2 * oscillator.cycles + oscillator.phase + phaseOffset) * oscillator.amp;
      }, 0);

      const perturbation =
        Math.sin(flowPosition * Math.PI * 2 * 18.5 + time * 0.006 + layer.phaseOffset) * 0.035 * energy +
        noiseAt(flowPosition * 0.94 + layer.phaseOffset * 0.08) * layer.noiseScale;

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

  const startTime = performance.now();
  primeSpeech(startTime);
  drawWaveform(startTime);
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
  const flagItems = Array.from(flagRing.children);
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

  const pointerFlagIndex = (event) => {
    const step = 360 / flagItems.length;
    const angle = pointerAngle(event);
    const relativeAngle = ((angle - orbitAngle) % 360 + 360) % 360;

    return relativeAngle / step;
  };

  const setOrbitAngle = () => {
    languageOrbit.style.setProperty("--orbit-angle", `${orbitAngle}deg`);
  };

  const resetFlagMagnification = () => {
    flagItems.forEach((flag) => {
      flag.classList.remove("is-active");
      flag.style.removeProperty("--flag-scale");
      flag.style.removeProperty("--flag-radius-push");
    });
  };

  const circularIndexDistance = (index, targetIndex, count) => {
    const distance = Math.abs(index - targetIndex);
    return Math.min(distance, count - distance);
  };

  const applyDockMagnification = (targetIndex) => {
    const count = flagItems.length;
    const range = 2.65;
    const maxScale = 2.75;
    const maxPush = 24;
    const nearestIndex = Math.round(targetIndex) % count;

    flagItems.forEach((flag, index) => {
      const distance = circularIndexDistance(index, targetIndex, count);
      const influence = Math.max(0, 1 - distance / range);
      const eased = influence * influence * (3 - 2 * influence);
      const scale = 1 + (maxScale - 1) * eased;
      const radiusPush = maxPush * eased;

      flag.style.setProperty("--flag-scale", scale.toFixed(3));
      flag.style.setProperty("--flag-radius-push", `${radiusPush.toFixed(2)}px`);
      flag.classList.toggle("is-active", index === nearestIndex);
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
    flag.addEventListener("focus", () => applyDockMagnification(index));
    flag.addEventListener("blur", resetFlagMagnification);
  });

  flagRing.addEventListener("pointerleave", () => {
    if (!isDragging) {
      flagRing.classList.remove("can-drag");
      resetFlagMagnification();
    }
  });

  flagRing.addEventListener("pointerdown", (event) => {
    if (!isOnFlagRing(event)) return;

    event.preventDefault();
    isDragging = true;
    applyDockMagnification(pointerFlagIndex(event));
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
        applyDockMagnification(pointerFlagIndex(event));
      } else {
        resetFlagMagnification();
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
    applyDockMagnification(pointerFlagIndex(event));
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
