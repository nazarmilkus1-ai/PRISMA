"use client";

import {
  Activity,
  BarChart3,
  Bell,
  BookMarked,
  BookOpen,
  CalendarDays,
  Check,
  ChevronRight,
  CircleAlert,
  ClipboardList,
  Compass,
  ExternalLink,
  Eye,
  FileClock,
  FileText,
  Flag,
  GitBranch as Github,
  Globe2,
  Home,
  LayoutDashboard,
  LineChart,
  ListChecks,
  LockKeyhole,
  LogOut,
  Map,
  Menu,
  Monitor,
  Moon,
  Newspaper,
  Search,
  Server,
  Settings2,
  ShoppingBag,
  Shield,
  ShieldCheck,
  Swords,
  Sun,
  Trophy,
  UserRound,
  UserRoundCog,
  Users,
  X,
  type LucideIcon,
} from "lucide-react";

export type IconName =
  | "activity"
  | "bar-chart"
  | "bell"
  | "book"
  | "calendar"
  | "check"
  | "chevron-right"
  | "alert"
  | "applications"
  | "compass"
  | "external"
  | "eye"
  | "file-clock"
  | "flag"
  | "github"
  | "globe"
  | "home"
  | "dashboard"
  | "logout"
  | "map"
  | "menu"
  | "moon"
  | "news"
  | "search"
  | "server"
  | "settings"
  | "clans"
  | "battle"
  | "profile"
  | "players"
  | "close"
  | "sun"
  | "monitor"
  | "analytics"
  | "reports"
  | "moderation"
  | "voting"
  | "admins"
  | "security"
  | "audit"
  | "ranking"
  | "market"
  | "wiki";

const icons: Record<IconName, LucideIcon> = {
  activity: Activity,
  "bar-chart": BarChart3,
  bell: Bell,
  book: BookOpen,
  calendar: CalendarDays,
  check: Check,
  "chevron-right": ChevronRight,
  alert: CircleAlert,
  applications: ClipboardList,
  compass: Compass,
  external: ExternalLink,
  eye: Eye,
  "file-clock": FileClock,
  flag: Flag,
  github: Github,
  globe: Globe2,
  home: Home,
  dashboard: LayoutDashboard,
  logout: LogOut,
  map: Map,
  menu: Menu,
  moon: Moon,
  news: Newspaper,
  search: Search,
  server: Server,
  settings: Settings2,
  clans: Shield,
  battle: Swords,
  profile: UserRound,
  players: Users,
  close: X,
  sun: Sun,
  monitor: Monitor,
  analytics: LineChart,
  reports: FileText,
  moderation: ShieldCheck,
  voting: ListChecks,
  admins: UserRoundCog,
  security: LockKeyhole,
  audit: FileClock,
  ranking: Trophy,
  market: ShoppingBag,
  wiki: BookMarked,
};

export function Icon({
  name,
  size = 16,
  strokeWidth = 1.75,
  className,
}: {
  name: IconName;
  size?: number;
  strokeWidth?: number;
  className?: string;
}) {
  const C = icons[name];
  return <C size={size} strokeWidth={strokeWidth} className={className} aria-hidden="true" />;
}
