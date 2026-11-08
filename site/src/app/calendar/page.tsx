import { requireModule, requireModuleMember, requireModuleUser } from "@/lib/access";
import { notFound } from "next/navigation";
import { getParticipantCalendar } from "@/lib/data";
import { CalendarTimeline } from "@/components/CalendarTimeline";

export const metadata = { title: "Календарь" };

export default async function CalendarPage() {
  await requireModule("events");
  const events = await getParticipantCalendar();

  return (
    <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <div className="mb-5">
        <p className="text-xs font-semibold uppercase tracking-[.18em] text-primary">PRISMA CALENDAR</p>
        <h1 className="mt-1 text-3xl font-semibold">Календарь</h1>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Все опубликованные события PRISMA в одной временной ленте. Зарегистрированные события
          отмечаются прямо в календаре.
        </p>
      </div>

      <CalendarTimeline events={events as any[]} />
    </div>
  );
}
