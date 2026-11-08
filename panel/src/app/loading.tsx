import { Skeleton } from "@prisma-eco/ui";

export default function Loading() {
  return (
    <div className="mx-auto flex min-h-[70vh] w-full max-w-7xl gap-4 p-4 sm:p-6">
      <Skeleton className="hidden w-56 shrink-0 rounded-xl lg:block" />
      <div className="min-w-0 flex-1 space-y-4">
        <Skeleton className="h-8 w-56" />
        <Skeleton className="h-24 w-full rounded-xl" />
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {Array.from({ length: 6 }, (_, index) => <Skeleton key={index} className="h-28 rounded-xl" />)}
        </div>
      </div>
    </div>
  );
}
