export function StatusBadge({ online, children }: { online: boolean; children: React.ReactNode }) {
  return (
    <span className="prisma-glass-badge inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-medium">
      <span className={online ? "size-2 rounded-full bg-emerald-500" : "size-2 rounded-full bg-neutral-400"} />
      {children}
    </span>
  );
}
