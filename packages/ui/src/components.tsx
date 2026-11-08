"use client";

import * as React from "react";
import { Icon, type IconName } from "./icon";
import { Card } from "./components/card";
import { Label } from "./components/label";
import { cn } from "cn";

export { Button, buttonVariants } from "./components/button";

export {
  Card,
  CardHeader,
  CardFooter,
  CardTitle,
  CardAction,
  CardDescription,
  CardContent,
} from "./components/card";

export { Badge, badgeVariants } from "./components/badge";

export { Label } from "./components/label"

export { Input } from "./components/input";

export { Textarea } from "./components/textarea";

export {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectScrollDownButton,
  SelectScrollUpButton,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from "./components/select";

export function FormField({label,description,error,required,children}:{label:string;description?:string;error?:string;required?:boolean;children:React.ReactNode}){
  const child=React.isValidElement(children)?children:null;
  const childProps=child?.props as {id?:string;name?:string} | undefined;
  const id=childProps?.id ?? childProps?.name;
  const descriptionId=id? id+"-description":undefined;
  const errorId=id? id+"-error":undefined;
  return <div className="grid gap-1.5">
    <div>
      <Label htmlFor={id}>{label}{required?<span aria-hidden className="ml-1 text-destructive">*</span>:null}</Label>
      {description?<p id={descriptionId} className="mt-1 text-xs text-muted-foreground">{description}</p>:null}
    </div>
    {children}
    {error?<p id={errorId} role="alert" className="text-xs text-destructive">{error}</p>:null}
  </div>;
}

export {
  Field,
  FieldLabel,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLegend,
  FieldSeparator,
  FieldSet,
  FieldContent,
  FieldTitle,
} from "./components/field";

export function PageHeader({eyebrow,title,description,actions,className}:{eyebrow?:string;title:string;description?:string;actions?:React.ReactNode;className?:string}){
 return <header className={cn("flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between",className)}>
  <div className="min-w-0">
   {eyebrow?<p className="mb-1 text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">{eyebrow}</p>:null}
   <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
   {description?<p className="mt-1 max-w-2xl text-sm leading-6 text-muted-foreground">{description}</p>:null}
  </div>
  {actions?<div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>:null}
 </header>;
}

export function EmptyState({icon="activity",title,description,action}:{icon?:IconName;title:string;description?:string;action?:React.ReactNode}){
 return <div className="flex min-h-52 flex-col items-center justify-center px-6 py-12 text-center">
  <span className="mb-3 flex size-9 items-center justify-center rounded-full border bg-muted"><Icon name={icon} size={16} className="text-muted-foreground"/></span>
  <h2 className="text-sm font-semibold">{title}</h2>
  {description?<p className="mt-1 max-w-sm text-sm text-muted-foreground">{description}</p>:null}
  {action?<div className="mt-4">{action}</div>:null}
 </div>;
}

export function Metric({label,value,hint,icon="activity"}:{label:string;value:React.ReactNode;hint?:string;icon?:IconName}){
 return <Card className="p-4">
  <div className="flex items-start justify-between gap-3">
   <div className="min-w-0"><p className="text-xs text-muted-foreground">{label}</p><p className="mt-2 text-2xl font-semibold tracking-tight">{value}</p>{hint?<p className="mt-1 text-xs text-muted-foreground">{hint}</p>:null}</div>
   <span className="flex size-8 shrink-0 items-center justify-center rounded-md bg-muted"><Icon name={icon} size={15} className="text-muted-foreground"/></span>
  </div>
 </Card>;
}

export { Table, TableHeader, TableBody, TableFooter, TableHead, TableRow, TableCell, TableCaption } from "./components/table";

export { Separator } from "./components/separator";
export { Skeleton } from "./components/skeleton";
export { Alert, AlertTitle, AlertDescription, AlertAction, alertVariants } from "./components/alert";
export { Tabs, TabsBase, TabsList, TabsTrigger, TabsContent } from "./components/tabs";
export { Pagination, PaginationContent, PaginationEllipsis, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, SimplePagination } from "./components/pagination";
export { Dialog, DialogTrigger, DialogPortal, DialogClose, DialogOverlay, DialogContent, DialogHeader, DialogFooter, DialogTitle, DialogDescription } from "./components/dialog";

export function InfoItem({
  label,
  value,
  children,
  className,
  valueClassName,
}: {
  label: string;
  value?: React.ReactNode;
  children?: React.ReactNode;
  className?: string;
  valueClassName?: string;
}) {
  return (
    <div className={cn("prisma-glass-surface rounded-md border p-3", className)}>
      <p className="text-xs text-muted-foreground">{label}</p>
      {children ?? <p className={cn("mt-1 break-words text-sm", valueClassName)}>{value}</p>}
    </div>
  );
}


export function PrismaNotificationToggle({
  checked = false,
  onCheckedChange,
  disabled = false,
  label = "Уведомления",
  className,
}: {
  checked?: boolean;
  onCheckedChange?: (checked: boolean) => void;
  disabled?: boolean;
  label?: string;
  className?: string;
}) {
  return (
    <label className={cn("prisma-notification-toggle", disabled && "is-disabled", className)}>
      <input
        type="checkbox"
        checked={checked}
        onChange={(event) => onCheckedChange?.(event.target.checked)}
        disabled={disabled}
        aria-label={label}
      />
      <span className="prisma-notification-toggle-icon" aria-hidden="true">
        <Icon name="bell" size={19} strokeWidth={1.8} />
        <Icon name="bell" size={19} strokeWidth={1.8} className="prisma-notification-toggle-solid" />
      </span>
    </label>
  );
}

export function VisuallyHidden({className,...props}:React.HTMLAttributes<HTMLSpanElement>){return <span className={cn("sr-only",className)} {...props}/>;}

