export function MediaInfoOverlay({
  lines,
  sidebarOpen,
}: {
  lines: string[];
  sidebarOpen: boolean;
}) {
  if (!lines.length) return null;

  return (
    <div
      className={[
        'absolute top-3 z-[60] pointer-events-none select-none',
        sidebarOpen ? 'left-[calc(280px+12px)] sm:left-[calc(320px+12px)]' : 'left-3',
      ].join(' ')}
    >
      <div className="rounded-lg bg-black/55 backdrop-blur-sm border border-white/10 px-3 py-2 text-[11px] leading-snug font-mono text-white max-w-[70vw] sm:max-w-[520px]">
        {lines.map((line, idx) => (
          <div key={idx} className="whitespace-pre-wrap">
            {line}
          </div>
        ))}
      </div>
    </div>
  );
}

