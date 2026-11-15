import { cn } from "../lib/cn";

export function Skeleton({ className, ...props }: { className?: string } & React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      data-slot="skeleton"
      className={cn("cn-skeleton animate-pulse", className)}
      {...props}
    />
  );
}
