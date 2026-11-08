import { Skeleton } from "@prisma-eco/ui";

export default function Loading() {
  return (
    <div className="space-y-6">
      <div>
        <Skeleton className="h-7 w-32" />
        <Skeleton className="mt-2 h-4 w-80 max-w-full" />
      </div>

      <div className="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_28rem]">
        <div className="overflow-hidden rounded-xl border bg-card">
          <div className="space-y-3 border-b p-4">
            <Skeleton className="h-10 w-full" />
            <div className="flex gap-2">
              <Skeleton className="h-7 w-14" />
              <Skeleton className="h-7 w-24" />
              <Skeleton className="h-7 w-20" />
              <Skeleton className="ml-auto h-7 w-20" />
            </div>
          </div>
          <div className="divide-y">
            {Array.from({ length: 8 }, (_, index) => (
              <div key={index} className="flex items-center gap-3 p-4">
                <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
                <div className="min-w-0 flex-1 space-y-2">
                  <Skeleton className="h-4 w-36 max-w-full" />
                  <Skeleton className="h-3 w-52 max-w-full" />
                  <Skeleton className="h-3 w-72 max-w-full" />
                </div>
                <Skeleton className="h-6 w-20 shrink-0 rounded-full" />
              </div>
            ))}
          </div>
        </div>

        <div className="rounded-xl border bg-card p-5">
          <div className="flex items-start gap-3">
            <Skeleton className="h-12 w-12 shrink-0 rounded-full" />
            <div className="flex-1 space-y-2">
              <Skeleton className="h-5 w-40" />
              <Skeleton className="h-3 w-56 max-w-full" />
              <Skeleton className="h-3 w-44 max-w-full" />
            </div>
          </div>
          <div className="mt-5 grid grid-cols-2 gap-2">
            {Array.from({ length: 4 }, (_, index) => <Skeleton key={index} className="h-16 rounded-lg" />)}
          </div>
          <div className="mt-5 space-y-2">
            {Array.from({ length: 6 }, (_, index) => <Skeleton key={index} className="h-9 rounded-lg" />)}
          </div>
        </div>
      </div>
    </div>
  );
}
