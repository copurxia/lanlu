'use client';

export interface HtmlSpreadMetrics {
  maxScrollLeft: number;
  scrollLeft: number;
  step: number;
  currentSlot: number;
  maxSlot: number;
}

export function getHtmlSpreadSlotOffset(maxScrollLeft: number, step: number, slot: number) {
  return Math.max(0, Math.min(maxScrollLeft, slot * step));
}

function toNumber(value: string | null | undefined) {
  const n = Number.parseFloat(value || '0');
  return Number.isFinite(n) ? n : 0;
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

  // Choose the closest valid slot offset; the last slot may clamp to maxScrollLeft
  // and cannot be derived reliably from simple scrollLeft / step rounding.
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
