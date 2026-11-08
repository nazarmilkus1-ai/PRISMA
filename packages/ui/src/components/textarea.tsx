import * as React from "react"
import { cn } from "cn"

function Textarea({
  className,
  id,
  ...props
}: React.ComponentProps<"textarea">) {
  const controlId = id ?? (typeof props.name === "string" ? props.name : undefined)

  return (
    <textarea
      id={controlId}
      data-slot="textarea"
      className={cn(
        "flex field-sizing-content min-h-16 w-full rounded-md border bg-background px-3 py-2 text-base shadow-xs outline-none transition-[color,box-shadow]",
        "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-ring/30 focus-visible:ring-3",
        "aria-invalid:border-destructive aria-invalid:ring-destructive/20",
        "disabled:cursor-not-allowed disabled:opacity-50",
        "md:text-sm",
        className,
      )}
      {...props}
    />
  )
}

export { Textarea }
