'use client';

export interface HtmlSpreadMetrics {
  maxScrollLeft: number;
  scrollLeft: number;
  step: number;
  currentSlot: number;
  maxSlot: number;
}

const spreadAnimationFrames = new WeakMap<HTMLElement, number>();
const DEFAULT_SPREAD_ANIMATION_MS = 320;

export function getHtmlSpreadSlotOffset(maxScrollLeft: number, step: number, slot: number) {
  return Math.max(0, Math.min(maxScrollLeft, slot * step));
}

function toNumber(value: string | null | undefined) {
  const n = Number.parseFloat(value || '0');
  return Number.isFinite(n) ? n : 0;
}

function easeOutBack(t: number) {
  const c1 = 0.6;
  const c3 = c1 + 1;
  return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
}

function stopSpreadAnimation(container: HTMLElement) {
  const frame = spreadAnimationFrames.get(container);
  if (frame != null) {
    cancelAnimationFrame(frame);
    spreadAnimationFrames.delete(container);
  }
}

export function animateHtmlSpreadTo(container: HTMLElement, targetLeft: number, durationMs = DEFAULT_SPREAD_ANIMATION_MS) {
  const maxScrollLeft = Math.max(0, container.scrollWidth - container.clientWidth);
  const clampedTarget = Math.max(0, Math.min(maxScrollLeft, targetLeft));
  const startLeft = container.scrollLeft;
  const distance = clampedTarget - startLeft;

  stopSpreadAnimation(container);

  if (Math.abs(distance) <= 1 || durationMs <= 0) {
    container.scrollLeft = clampedTarget;
    return;
  }

  const startAt = performance.now();

  const tick = (now: number) => {
    const elapsed = now - startAt;
    const progress = Math.max(0, Math.min(1, elapsed / durationMs));
    const eased = easeOutBack(progress);
    const nextLeft = startLeft + distance * eased;
    container.scrollLeft = Math.max(0, Math.min(maxScrollLeft, nextLeft));

    if (progress < 1) {
      const frame = requestAnimationFrame(tick);
      spreadAnimationFrames.set(container, frame);
      return;
    }

    container.scrollLeft = clampedTarget;
    spreadAnimationFrames.delete(container);
  };

  const frame = requestAnimationFrame(tick);
  spreadAnimationFrames.set(container, frame);
}

export function getHtmlSpreadTurnTarget(container: HTMLElement, direction: 'prev' | 'next') {
  const metrics = getHtmlSpreadMetrics(container);
  if (metrics.maxScrollLeft <= 1) return null;

  if (direction === 'next') {
    if (metrics.currentSlot >= metrics.maxSlot) return null;
    const targetSlot = Math.min(metrics.maxSlot, metrics.currentSlot + 1);
    return getHtmlSpreadSlotOffset(metrics.maxScrollLeft, metrics.step, targetSlot);
  }

  if (metrics.currentSlot <= 0) return null;
  const targetSlot = Math.max(0, metrics.currentSlot - 1);
  return getHtmlSpreadSlotOffset(metrics.maxScrollLeft, metrics.step, targetSlot);
}

export function stepHtmlSpread(container: HTMLElement, direction: 'prev' | 'next', durationMs = DEFAULT_SPREAD_ANIMATION_MS) {
  const target = getHtmlSpreadTurnTarget(container, direction);
  if (target == null) return false;
  animateHtmlSpreadTo(container, target, durationMs);
  return true;
}

/**
 * Calculate consistent spread metrics for the HTML double-page (two-column) layout.
 * CSS multi-column introduces a gap between *every* column, so the stride between
 * spread starts is not equal to container.clientWidth.
 */
export function getHtmlSpreadMetrics(container: HTMLElement): HtmlSpreadMetrics {
  const content =
    (container.querySelector('.reader-html-spread-content') as HTMLElement | null) || container;
  const style = window.getComputedStyle(content);
  const paddingLeft = toNumber(style.paddingLeft);
  const paddingRight = toNumber(style.paddingRight);
  const columnGap = toNumber(style.columnGap);

  const contentBoxWidth = Math.max(1, content.clientWidth - paddingLeft - paddingRight);
  const singleColumnWidth = Math.max(1, (contentBoxWidth - columnGap) / 2);
  const step = Math.max(1, 2 * (singleColumnWidth + columnGap));

  const maxScrollLeft = Math.max(0, container.scrollWidth - container.clientWidth);
  const scrollLeft = Math.max(0, Math.min(maxScrollLeft, container.scrollLeft));
  const maxSlot = Math.max(0, Math.ceil(maxScrollLeft / step));

  const roughSlot = Math.max(0, Math.min(maxSlot, Math.round(scrollLeft / step)));
  let currentSlot = roughSlot;
  let bestDistance = Math.abs(scrollLeft - getHtmlSpreadSlotOffset(maxScrollLeft, step, roughSlot));

  const candidateSlots = [roughSlot - 1, roughSlot + 1, 0, maxSlot];
  for (const slot of candidateSlots) {
    if (slot < 0 || slot > maxSlot) continue;
    const offset = getHtmlSpreadSlotOffset(maxScrollLeft, step, slot);
    const distance = Math.abs(scrollLeft - offset);
    if (distance < bestDistance) {
      bestDistance = distance;
      currentSlot = slot;
    }
  }

  return {
    maxScrollLeft,
    scrollLeft,
    step,
    currentSlot,
    maxSlot,
  };
}
