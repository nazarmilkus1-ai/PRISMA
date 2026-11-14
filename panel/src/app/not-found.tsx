import Link from "next/link";
import { buttonVariants } from "@prisma-eco/ui";

export default function NotFound() {
  return (
    <main className="mx-auto grid min-h-[70vh] max-w-xl place-items-center px-4 py-16">
      <div className="w-full rounded-2xl border bg-card p-8 text-center">
        <p className="text-sm font-semibold tracking-widest text-muted-foreground">404</p>
        <h1 className="mt-2 text-2xl font-bold">Такой страницы нет</h1>
        <p className="mt-2 text-sm text-muted-foreground">Ссылка устарела или в адресе опечатка.</p>
        <div className="mt-6 flex flex-wrap justify-center gap-3">
          <Link href="/dashboard" className={buttonVariants({ variant: "outline" })}>Дашборд</Link>
          <Link href="/" className={buttonVariants()}>В панель</Link>
        </div>
      </div>
    </main>
  );
}
