"use client"

import * as React from "react"
import { ChevronLeft, ChevronRight, MoreHorizontal } from "lucide-react"
import { cn } from "cn"

import { Button } from "./button"

function Pagination({ className, ...props }: React.ComponentProps<"nav">) {
  return (
    <nav
      role="navigation"
      aria-label="pagination"
      data-slot="pagination"
      className={cn(
        "cn-pagination mx-auto flex w-full justify-center",
        className
      )}
      {...props}
    />
  )
}

function PaginationContent({ className, ...props }: React.ComponentProps<"ul">) {
  return (
    <ul
      data-slot="pagination-content"
      className={cn("cn-pagination-content flex items-center", className)}
      {...props}
    />
  )
}

function PaginationItem({ ...props }: React.ComponentProps<"li">) {
  return <li data-slot="pagination-item" {...props} />
}

type PaginationLinkProps = {
  isActive?: boolean
} & Pick<React.ComponentProps<typeof Button>, "size"> &
  React.ComponentProps<"a">

function PaginationLink({
  className,
  isActive,
  size = "icon",
  ...props
}: PaginationLinkProps) {
  return (
    <Button
      variant={isActive ? "outline" : "ghost"}
      size={size}
      className={cn("cn-pagination-link", className)}
      nativeButton={false}
      render={
        <a
          aria-current={isActive ? "page" : undefined}
          data-slot="pagination-link"
          data-active={isActive}
          {...props}
        />
      }
    />
  )
}

function PaginationPrevious({
  className,
  text = "Previous",
  ...props
}: React.ComponentProps<typeof PaginationLink> & { text?: string }) {
  return (
    <PaginationLink
      aria-label="Go to previous page"
      size="default"
      className={cn("cn-pagination-previous", className)}
      {...props}
    >
      <ChevronLeft data-icon="inline-start" className="cn-rtl-flip" />
      <span className="cn-pagination-previous-text hidden sm:block">{text}</span>
    </PaginationLink>
  )
}

function PaginationNext({
  className,
  text = "Next",
  ...props
}: React.ComponentProps<typeof PaginationLink> & { text?: string }) {
  return (
    <PaginationLink
      aria-label="Go to next page"
      size="default"
      className={cn("cn-pagination-next", className)}
      {...props}
    >
      <span className="cn-pagination-next-text hidden sm:block">{text}</span>
      <ChevronRight data-icon="inline-end" className="cn-rtl-flip" />
    </PaginationLink>
  )
}

function PaginationEllipsis({ className, ...props }: React.ComponentProps<"span">) {
  return (
    <span
      aria-hidden
      data-slot="pagination-ellipsis"
      className={cn(
        "cn-pagination-ellipsis flex items-center justify-center",
        className
      )}
      {...props}
    >
      <MoreHorizontal />
      <span className="sr-only">More pages</span>
    </span>
  )
}

type SimplePaginationProps = {
  page: number
  totalPages: number
  onChange: (page: number) => void
}

function SimplePagination({ page, totalPages, onChange }: SimplePaginationProps) {
  if (totalPages <= 1) return null

  return (
    <div className="flex items-center justify-between gap-3 text-xs text-muted-foreground">
      <span>Страница {page} из {totalPages}</span>
      <div className="flex gap-1">
        <PaginationLink
          href="#"
          aria-label="Предыдущая страница"
          size="icon"
          onClick={(event) => {
            event.preventDefault()
            if (page > 1) onChange(page - 1)
          }}
          aria-disabled={page <= 1}
          className="size-8"
        >
          <ChevronLeft size={15} />
        </PaginationLink>
        <PaginationLink
          href="#"
          aria-label="Следующая страница"
          size="icon"
          onClick={(event) => {
            event.preventDefault()
            if (page < totalPages) onChange(page + 1)
          }}
          aria-disabled={page >= totalPages}
          className="size-8"
        >
          <ChevronRight size={15} />
        </PaginationLink>
      </div>
    </div>
  )
}

export { Pagination, PaginationContent, PaginationEllipsis, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, SimplePagination }
