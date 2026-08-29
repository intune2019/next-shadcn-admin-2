"use client";

import { useRef, useState } from "react";
import type { DragEvent } from "react";

import { HelpCircle, Trash2, Upload } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

export default function FileUpload01() {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploadedFiles, setUploadedFiles] = useState<File[]>([]);
  const [fileProgresses, setFileProgresses] = useState<Record<string, number>>({});

  const handleFileSelect = (files: FileList | null) => {
    if (!files) return;

    const newFiles = Array.from(files);
    setUploadedFiles((prev) => [...prev, ...newFiles]);

    newFiles.forEach((file) => {
      let progress = 0;
      const interval = setInterval(() => {
        progress += Math.random() * 10;
        if (progress >= 100) {
          progress = 100;
          clearInterval(interval);
        }
        setFileProgresses((prev) => ({
          ...prev,
          [file.name]: Math.min(progress, 100),
        }));
      }, 300);
    });
  };

  const handleBoxClick = () => {
    fileInputRef.current?.click();
  };

  const handleDragOver = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault();
  };

  const handleDrop = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    handleFileSelect(e.dataTransfer.files);
  };

  const removeFile = (filename: string) => {
    setUploadedFiles((prev) => prev.filter((file) => file.name !== filename));
    setFileProgresses((prev) => {
      const newProgresses = { ...prev };
      delete newProgresses[filename];
      return newProgresses;
    });
  };

  return (
    <div className="flex items-center justify-center p-10">
      <Card className="mx-auto w-full max-w-lg rounded-lg bg-background p-0 shadow-md">
        <CardContent className="p-0">
          <div className="p-6 pb-4">
            <div className="flex items-start justify-between">
              <div>
                <h2 className="text-balance text-lg font-medium text-foreground">Create a new project</h2>
                <p className="mt-1 text-pretty text-sm text-muted-foreground">Drag and drop files to create a new project.</p>
              </div>
            </div>
          </div>

          <div className="mt-2 px-6 pb-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label className="mb-2" htmlFor="project-name">
                  Project name
                </Label>
                <Input defaultValue="Open Source Stripe" id="project-name" type="text" />
              </div>

              <div>
                <Label className="mb-2" htmlFor="project-lead">
                  Project lead
                </Label>
                <Select defaultValue="1">
                  <SelectTrigger className="w-full ps-2" id="project-lead">
                    <SelectValue placeholder="Select project lead" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectGroup>
                      <SelectItem value="1">
                        <img
                          alt="Ephraim Duncan"
                          className="size-5 rounded"
                          height={20}
                          src="https://blocks.so/avatar-01.png"
                          width={20}
                        />
                        <span className="truncate">Ephraim Duncan</span>
                      </SelectItem>
                      <SelectItem value="2">
                        <img
                          alt="Lucas Smith"
                          className="size-5 rounded"
                          height={20}
                          src="https://blocks.so/avatar-03.png"
                          width={20}
                        />
                        <span className="truncate">Lucas Smith</span>
                      </SelectItem>
                      <SelectItem value="3">
                        <img
                          alt="Timur Ercan"
                          className="size-5 rounded"
                          height={20}
                          src="https://blocks.so/avatar-02.jpg"
                          width={20}
                        />
                        <span className="truncate">Timur Ercan</span>
                      </SelectItem>
                    </SelectGroup>
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>

          <div className="px-6">
            <div
              className="flex h-48 cursor-pointer flex-col items-center justify-center rounded-md border-2 border-dashed border-border p-8 text-center"
              onClick={handleBoxClick}
              onDragOver={handleDragOver}
              onDrop={handleDrop}
            >
              <div className="mb-2 rounded-full bg-muted p-3">
                <Upload className="h-5 w-5 text-muted-foreground" />
              </div>
              <p className="text-pretty text-sm font-medium text-foreground">Upload a project image</p>
              <p className="mt-1 text-pretty text-sm text-muted-foreground">
                or, <label className="cursor-pointer font-medium text-primary hover:text-primary/90" htmlFor="file-upload-01" onClick={(e) => e.stopPropagation()}>
                  click to browse
                </label>{" "}(4MB max)
              </p>
              <input
                accept="image/*"
                className="hidden"
                id="file-upload-01"
                onChange={(e) => handleFileSelect(e.target.files)}
                ref={fileInputRef}
                type="file"
              />
            </div>
          </div>

          <div className={cn("space-y-3 px-6 pb-5", uploadedFiles.length > 0 ? "mt-4" : "")}>
            {uploadedFiles.map((file, index) => {
              const imageUrl = URL.createObjectURL(file);

              return (
                <div className="flex flex-col rounded-lg border border-border p-2" key={file.name + index}>
                  <div className="flex items-center gap-2">
                    <div className="row-span-2 flex h-14 w-18 shrink-0 items-center justify-center self-start overflow-hidden rounded-sm bg-muted">
                      <img alt={file.name} className="h-full w-full object-cover" src={imageUrl} />
                    </div>

                    <div className="flex-1 pr-1">
                      <div className="flex items-center justify-between">
                        <div className="flex min-w-0 items-center gap-2">
                          <span className="max-w-[250px] truncate text-sm text-foreground">{file.name}</span>
                          <span className="whitespace-nowrap text-sm text-muted-foreground">
                            {Math.round(file.size / 1024)} KB
                          </span>
                        </div>
                        <Button
                          type="button"
                          className="bg-transparent! hover:text-red-500"
                          onClick={() => removeFile(file.name)}
                          size="icon-sm"
                          variant="ghost"
                          aria-label={`Remove ${file.name}`}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>

                      <div className="flex items-center gap-2">
                        <div className="h-2 flex-1 overflow-hidden rounded-full bg-muted">
                          <div
                            className="h-full bg-primary"
                            style={{ width: `${fileProgresses[file.name] || 0}%` }}
                          />
                        </div>
                        <span className="whitespace-nowrap text-xs text-muted-foreground">
                          {Math.round(fileProgresses[file.name] || 0)}%
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>

          <div className="flex items-center justify-between rounded-b-lg border-t border-border bg-muted px-6 py-3">
            <TooltipProvider delayDuration={0}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button className="flex items-center text-muted-foreground hover:text-foreground" size="sm" variant="ghost">
                    <HelpCircle className="mr-1 h-4 w-4" />
                    Need help?
                  </Button>
                </TooltipTrigger>
                <TooltipContent className="border bg-background py-3 text-foreground">
                  <div className="space-y-1">
                    <p className="text-pretty text-[13px] font-medium">Need assistance?</p>
                    <p className="max-w-[200px] text-pretty text-xs text-muted-foreground">
                      Upload project images by dragging and dropping files or using the file browser. Supported formats:
                      JPG, PNG, SVG. Maximum file size: 4MB.
                    </p>
                  </div>
                </TooltipContent>
              </Tooltip>
            </TooltipProvider>

            <div className="flex gap-2">
              <Button className="h-9 px-4 text-sm font-medium" variant="outline">
                Cancel
              </Button>
              <Button className="h-9 px-4 text-sm font-medium">Continue</Button>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
