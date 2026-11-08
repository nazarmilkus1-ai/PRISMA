"use client";

import * as React from "react";
import { FileText, UploadCloud, X } from "lucide-react";
import { cn } from "cn";

export interface PrismaFileUploadProps {
  onChange?: (files: File[]) => void;
  multiple?: boolean;
  accept?: string;
  disabled?: boolean;
  maxFiles?: number;
  className?: string;
}

export function PrismaFileUpload({
  onChange,
  multiple = true,
  accept,
  disabled = false,
  maxFiles,
  className,
}: PrismaFileUploadProps) {
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [files, setFiles] = React.useState<File[]>([]);
  const [dragActive, setDragActive] = React.useState(false);

  const updateFiles = React.useCallback(
    (incoming: FileList | File[]) => {
      if (disabled) return;

      const next = Array.from(incoming);
      const merged = multiple ? [...files, ...next] : next.slice(0, 1);
      const unique = merged.filter(
        (file, index, all) =>
          index ===
          all.findIndex(
            (candidate) =>
              candidate.name === file.name &&
              candidate.size === file.size &&
              candidate.lastModified === file.lastModified,
          ),
      );
      const limited = maxFiles ? unique.slice(0, maxFiles) : unique;

      setFiles(limited);
      onChange?.(limited);
    },
    [disabled, files, maxFiles, multiple, onChange],
  );

  const removeFile = (index: number) => {
    const next = files.filter((_, fileIndex) => fileIndex !== index);
    setFiles(next);
    onChange?.(next);
  };

  const handleDrop = (event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    setDragActive(false);
    updateFiles(event.dataTransfer.files);
  };

  const handleInputChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    if (event.target.files) updateFiles(event.target.files);
    event.target.value = "";
  };

  return (
    <div
      className={cn(
        "prisma-file-upload",
        dragActive && "is-drag-active",
        disabled && "is-disabled",
        className,
      )}
      onDragEnter={(event) => {
        event.preventDefault();
        if (!disabled) setDragActive(true);
      }}
      onDragOver={(event) => event.preventDefault()}
      onDragLeave={(event) => {
        if (event.currentTarget === event.target) setDragActive(false);
      }}
      onDrop={handleDrop}
    >
      <input
        ref={inputRef}
        className="sr-only"
        type="file"
        accept={accept}
        multiple={multiple}
        disabled={disabled}
        onChange={handleInputChange}
      />

      <button
        type="button"
        className="prisma-file-upload-dropzone"
        disabled={disabled}
        onClick={() => inputRef.current?.click()}
        aria-label="Выбрать файлы"
      >
        <span className="prisma-file-upload-icon" aria-hidden="true">
          <UploadCloud />
        </span>

        <span className="prisma-file-upload-copy">
          <strong>Перетащите файлы сюда</strong>
          <span>или нажмите, чтобы выбрать с устройства</span>
          {accept ? <small>Разрешённые форматы: {accept}</small> : null}
        </span>
      </button>

      {files.length > 0 ? (
        <div className="prisma-file-upload-list" aria-live="polite">
          {files.map((file, index) => (
            <div
              className="prisma-file-upload-file"
              key={file.name + file.lastModified + index}
            >
              <span
                className="prisma-file-upload-file-icon"
                aria-hidden="true"
              >
                <FileText />
              </span>
              <span className="prisma-file-upload-file-meta">
                <strong title={file.name}>{file.name}</strong>
                <small>{formatFileSize(file.size)}</small>
              </span>
              <button
                type="button"
                className="prisma-file-upload-remove"
                onClick={() => removeFile(index)}
                aria-label={`Удалить файл ${file.name}`}
              >
                <X />
              </button>
            </div>
          ))}
        </div>
      ) : null}
    </div>
  );
}

function formatFileSize(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024)
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}
