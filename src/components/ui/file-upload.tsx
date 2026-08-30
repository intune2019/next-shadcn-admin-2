"use client";

import { useRef, useState } from "react";
import type { ChangeEvent, DragEvent } from "react";

import { File as FileIcon, UploadCloud, X } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

export default function FileUpload() {
  const [dragActive, setDragActive] = useState(false);
  const [files, setFiles] = useState<File[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleDrag = (e: DragEvent<HTMLElement>) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.type === "dragenter" || e.type === "dragover") {
      setDragActive(true);
    } else if (e.type === "dragleave") {
      setDragActive(false);
    }
  };

  const handleDrop = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);

    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      const newFiles = Array.from(e.dataTransfer.files);
      setFiles((prev) => [...prev, ...newFiles]);
    }
  };

  const handleChange = (e: ChangeEvent<HTMLInputElement>) => {
    e.preventDefault();
    if (e.target.files && e.target.files[0]) {
      const newFiles = Array.from(e.target.files);
      setFiles((prev) => [...prev, ...newFiles]);
    }
  };

  const onButtonClick = () => {
    inputRef.current?.click();
  };

  const removeFile = (indexToRemove: number) => {
    setFiles(files.filter((_, index) => index !== indexToRemove));
  };

  const formatSize = (bytes: number) => {
    if (bytes === 0) return "0 Bytes";
    const k = 1024;
    const sizes = ["Bytes", "KB", "MB", "GB"];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
  };

  return (
    <div className="mx-auto w-full max-w-md rounded-xl border border-border bg-card p-6 font-sans text-card-foreground shadow-sm transition-colors duration-200">
      <div className="mb-6 text-center">
        <h2 className="text-xl font-semibold text-foreground">Upload your files</h2>
        <p className="mt-1 text-sm text-muted-foreground">PNG, JPG, PDF up to 10MB</p>
      </div>

      <form onDragEnter={handleDrag} onSubmit={(e) => e.preventDefault()} className="relative">
        <input ref={inputRef} type="file" multiple onChange={handleChange} className="hidden" />

        <div
          className={`flex h-48 w-full cursor-pointer flex-col items-center justify-center rounded-lg border-2 border-dashed transition-colors duration-200 ease-in-out ${
            dragActive
              ? "border-primary bg-primary/10 dark:bg-primary/5"
              : "border-border bg-muted/50 hover:bg-muted dark:bg-muted/10 dark:hover:bg-muted/20"
          }`}
          onClick={onButtonClick}
          onDragEnter={handleDrag}
          onDragLeave={handleDrag}
          onDragOver={handleDrag}
          onDrop={handleDrop}
        >
          <UploadCloud className={`mb-3 h-10 w-10 ${dragActive ? "text-primary" : "text-muted-foreground"}`} />
          <p className="text-sm font-medium text-foreground">
            Drag & drop files or <span className="text-primary transition-colors hover:text-primary/80">Browse</span>
          </p>
        </div>
      </form>

      {files.length > 0 && (
        <div className="mt-6 space-y-3">
          <h3 className="text-sm font-medium text-foreground">Selected Files</h3>
          <div className="max-h-48 space-y-2 overflow-y-auto pr-1">
            {files.map((file, index) => (
              <div
                key={`${file.name}-${index}`}
                className="group flex items-center justify-between rounded-lg border border-border bg-muted/30 p-3 transition-colors hover:border-primary/50 dark:bg-muted/10"
              >
                <div className="flex min-w-0 items-center space-x-3 overflow-hidden">
                  <div className="shrink-0 rounded border border-border/50 bg-background p-2 text-primary shadow-sm dark:bg-muted/20">
                    <FileIcon className="h-5 w-5" />
                  </div>
                  <div className="flex min-w-0 flex-col overflow-hidden">
                    <span className="truncate text-sm font-medium text-foreground">{file.name}</span>
                    <span className="text-xs text-muted-foreground">{formatSize(file.size)}</span>
                  </div>
                </div>
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  onClick={() => removeFile(index)}
                  className="h-8 w-8 shrink-0 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
                  aria-label="Remove file"
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
