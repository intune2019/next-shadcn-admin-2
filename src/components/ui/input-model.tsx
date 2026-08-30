"use client";

import { useState } from "react";

import { ArrowDownNarrowWide, ChevronDown, Clock, Copy, FileImage, FileText, FolderOpen, Globe, Headphones, Link, Play, Search, Star, Upload, X } from "lucide-react";

import { Avatar, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger } from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

interface Project {
  id: string;
  name: string;
  type: "pdf" | "url" | "audio";
  size?: string;
  duration?: string;
  createdAt: string;
  thumbnail?: string;
  status: "completed" | "processing" | "draft";
}

const mockProjects: Project[] = [
  {
    id: "1",
    name: "Future Thinking Talk.pdf",
    type: "pdf",
    size: "45.4 KB",
    createdAt: "2 hours ago",
    status: "completed",
  },
  {
    id: "2",
    name: "AI Revolution Article",
    type: "url",
    duration: "12:34",
    createdAt: "1 day ago",
    status: "completed",
  },
  {
    id: "3",
    name: "Tech Trends 2024",
    type: "audio",
    duration: "8:45",
    createdAt: "3 days ago",
    status: "processing",
  },
  {
    id: "4",
    name: "Climate Change Report",
    type: "pdf",
    size: "2.1 MB",
    createdAt: "1 week ago",
    status: "draft",
  },
];

export default function InputModel() {
  const [isOpen, setIsOpen] = useState(true);
  const [activeTab, setActiveTab] = useState("upload");
  const [urlInput, setUrlInput] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedProject, setSelectedProject] = useState<string | null>(null);
  const [selected, setSelected] = useState("morgan");
  const [selected2, setSelected2] = useState("");
  const [selected3, setSelected3] = useState("");
  const [selected4, setSelected4] = useState("");
  const [selected5, setSelected5] = useState("");
  const [selected6, setSelected6] = useState("");

  const filteredProjects = mockProjects.filter((project) =>
    project.name.toLowerCase().includes(searchQuery.toLowerCase()),
  );

  const getProjectIcon = (type: string) => {
    switch (type) {
      case "pdf":
        return <FileText className="h-4 w-4" />;
      case "url":
        return <Globe className="h-4 w-4" />;
      case "audio":
        return <Headphones className="h-4 w-4" />;
      default:
        return <FileText className="h-4 w-4" />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case "completed":
        return "bg-green-100 text-green-800 dark:bg-green-900/20 dark:text-green-400";
      case "processing":
        return "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400";
      case "draft":
        return "bg-neutral-100 text-neutral-800 dark:bg-neutral-800 dark:text-neutral-400";
      default:
        return "bg-neutral-100 text-neutral-800 dark:bg-neutral-800 dark:text-neutral-400";
    }
  };

  if (!isOpen) {
    return (
      <div className="flex items-center justify-center">
        <Button onClick={() => setIsOpen(true)}>Open Audio Show Creator</Button>
      </div>
    );
  }

  return (
    <div className="flex items-center justify-center p-4">
      <Card className="max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-3xl border-neutral-200 bg-white shadow-2xl dark:border-neutral-800 dark:bg-neutral-950">
        <CardContent className="h-full overflow-y-auto p-4 sm:p-6 lg:p-8">
          <div className="mb-6 flex items-start justify-between">
            <div className="flex min-w-0 flex-1 gap-3 sm:gap-4">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-neutral-800 dark:bg-neutral-700 sm:h-12 sm:w-12">
                <Headphones className="h-5 w-5 text-white sm:h-6 sm:w-6" />
              </div>
              <div className="min-w-0 flex-1">
                <h1 className="mb-2 text-base font-semibold text-neutral-900 dark:text-neutral-100 sm:text-lg">
                  Create Your Audio Show
                </h1>
                <p className="text-sm font-normal leading-relaxed text-neutral-600 dark:text-neutral-400">
                  Drop a document or paste a link — GenFM will instantly turn it into a fully voiced podcast you can
                  preview, edit, and download.
                </p>
              </div>
            </div>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setIsOpen(false)}
              className="-mt-2 -mr-2 shrink-0 text-neutral-400 hover:text-neutral-600 dark:text-neutral-500 dark:hover:text-neutral-300"
            >
              <X className="h-5 w-5" />
            </Button>
          </div>

          <Tabs value={activeTab} onValueChange={setActiveTab} className="mb-6 sm:mb-8">
            <TabsList className="grid w-full grid-cols-3 rounded-xl bg-neutral-100 p-1 dark:bg-neutral-800">
              <TabsTrigger
                value="upload"
                className="rounded-lg text-xs font-medium data-[state=active]:bg-white data-[state=active]:text-neutral-900 dark:data-[state=active]:bg-neutral-700 dark:data-[state=active]:text-neutral-100 sm:text-sm"
              >
                <Upload className="mr-1 h-4 w-4 sm:mr-2" />
                <span className="hidden sm:inline">Upload File</span>
                <span className="sm:hidden">Upload</span>
              </TabsTrigger>
              <TabsTrigger
                value="url"
                className="rounded-lg text-xs font-medium data-[state=active]:bg-white data-[state=active]:text-neutral-900 dark:data-[state=active]:bg-neutral-700 dark:data-[state=active]:text-neutral-100 sm:text-sm"
              >
                <Link className="mr-1 h-4 w-4 sm:mr-2" />
                <span className="hidden sm:inline">Import via URL</span>
                <span className="sm:hidden">URL</span>
              </TabsTrigger>
              <TabsTrigger
                value="existing"
                className="rounded-lg text-xs font-medium data-[state=active]:bg-white data-[state=active]:text-neutral-900 dark:data-[state=active]:bg-neutral-700 dark:data-[state=active]:text-neutral-100 sm:text-sm"
              >
                <FolderOpen className="mr-1 h-4 w-4 sm:mr-2" />
                <span className="hidden sm:inline">Choose Existing</span>
                <span className="sm:hidden">Existing</span>
              </TabsTrigger>
            </TabsList>

            <TabsContent value="upload" className="mt-6">
              <div className="rounded-xl border-2 border-dashed border-neutral-300 bg-neutral-50 p-8 text-center dark:border-neutral-700 dark:bg-neutral-900/50">
                <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-neutral-200 dark:bg-neutral-800">
                  <Upload className="h-6 w-6 text-neutral-600 dark:text-neutral-400" />
                </div>
                <h3 className="mb-2 text-lg font-medium text-neutral-900 dark:text-neutral-100">Drop your file here</h3>
                <p className="mb-4 text-neutral-600 dark:text-neutral-400">
                  Support for PDF, DOCX, TXT files up to 10MB
                </p>
                <Button variant="outline" className="border-neutral-300 bg-transparent dark:border-neutral-700">
                  Browse Files
                </Button>
              </div>
            </TabsContent>

            <TabsContent value="url" className="mt-6">
              <div className="space-y-4">
                <div>
                  <Label htmlFor="url-input" className="text-sm font-medium text-neutral-900 dark:text-neutral-100">
                    Content URL
                  </Label>
                  <div className="mt-2">
                    <Input
                      id="url-input"
                      type="url"
                      placeholder="https://example.com/article or YouTube URL"
                      value={urlInput}
                      onChange={(e) => setUrlInput(e.target.value)}
                      className="h-12 w-full rounded-xl border-neutral-300 bg-white dark:border-neutral-700 dark:bg-neutral-900"
                    />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                  <div className="flex items-center gap-2 rounded-lg border border-neutral-200 bg-neutral-50 p-3 dark:border-neutral-700 dark:bg-neutral-900/50">
                    <Globe className="h-4 w-4 text-neutral-600 dark:text-neutral-400" />
                    <span className="text-xs text-neutral-600 dark:text-neutral-400">Articles</span>
                  </div>
                  <div className="flex items-center gap-2 rounded-lg border border-neutral-200 bg-neutral-50 p-3 dark:border-neutral-700 dark:bg-neutral-900/50">
                    <Play className="h-4 w-4 text-neutral-600 dark:text-neutral-400" />
                    <span className="text-xs text-neutral-600 dark:text-neutral-400">YouTube</span>
                  </div>
                  <div className="flex items-center gap-2 rounded-lg border border-neutral-200 bg-neutral-50 p-3 dark:border-neutral-700 dark:bg-neutral-900/50">
                    <FileText className="h-4 w-4 text-neutral-600 dark:text-neutral-400" />
                    <span className="text-xs text-neutral-600 dark:text-neutral-400">Blogs</span>
                  </div>
                  <div className="flex items-center gap-2 rounded-lg border border-neutral-200 bg-neutral-50 p-3 dark:border-neutral-700 dark:bg-neutral-900/50">
                    <FileImage className="h-4 w-4 text-neutral-600 dark:text-neutral-400" />
                    <span className="text-xs text-neutral-600 dark:text-neutral-400">News</span>
                  </div>
                </div>
                {urlInput && (
                  <div className="rounded-xl border border-neutral-200 bg-neutral-50 p-4 dark:border-neutral-700 dark:bg-neutral-900/50">
                    <div className="flex items-center gap-3">
                      <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-neutral-200 dark:bg-neutral-800">
                        <Globe className="h-4 w-4 text-neutral-600 dark:text-neutral-400" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium text-neutral-900 dark:text-neutral-100">
                          Ready to import content
                        </p>
                        <p className="truncate text-xs text-neutral-600 dark:text-neutral-400">{urlInput}</p>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </TabsContent>

            <TabsContent value="existing" className="mt-6">
              <div className="space-y-4">
                <div className="relative">
                  <Search className="absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-neutral-400" />
                  <Input
                    placeholder="Search projects..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="h-12 rounded-xl border-neutral-300 bg-white pl-10 dark:border-neutral-700 dark:bg-neutral-900"
                  />
                </div>
                <div className="max-h-64 space-y-2 overflow-y-auto">
                  {filteredProjects.map((project) => (
                    <div
                      key={project.id}
                      onClick={() => setSelectedProject(project.id)}
                      className={`cursor-pointer rounded-xl border p-4 transition-all ${
                        selectedProject === project.id
                          ? "border-neutral-400 bg-neutral-100 dark:border-neutral-600 dark:bg-neutral-800"
                          : "border-neutral-200 bg-white hover:border-neutral-300 dark:border-neutral-700 dark:bg-neutral-900/50 dark:hover:border-neutral-600"
                      }`}
                    >
                      <div className="flex items-center gap-3">
                        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-neutral-200 dark:bg-neutral-800">
                          {getProjectIcon(project.type)}
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="mb-1 flex items-center gap-2">
                            <p className="truncate text-sm font-medium text-neutral-900 dark:text-neutral-100">
                              {project.name}
                            </p>
                            <Badge className={`px-2 py-0.5 text-xs ${getStatusColor(project.status)}`}>
                              {project.status}
                            </Badge>
                          </div>
                          <div className="flex items-center gap-4 text-xs text-neutral-600 dark:text-neutral-400">
                            <span className="flex items-center gap-1">
                              <Clock className="h-3 w-3" />
                              {project.createdAt}
                            </span>
                            {project.size && <span>{project.size}</span>}
                            {project.duration && (
                              <span className="flex items-center gap-1">
                                <Play className="h-3 w-3" />
                                {project.duration}
                              </span>
                            )}
                          </div>
                        </div>
                        <div className="flex items-center gap-1">
                          <Button variant="ghost" size="icon" className="h-8 w-8">
                            <Copy className="h-3 w-3" />
                          </Button>
                          <Button variant="ghost" size="icon" className="h-8 w-8">
                            <Star className="h-3 w-3" />
                          </Button>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </TabsContent>
          </Tabs>

          <div className="space-y-6">
            <div>
              <Label className="mb-3 block text-sm font-medium text-neutral-900 dark:text-neutral-100">Format Style</Label>
              <Select defaultValue="default" onValueChange={setSelected5}>
                <SelectTrigger className="h-12 w-full rounded-xl border-neutral-300 bg-white dark:border-neutral-700 dark:bg-neutral-900">
                  <div className="flex w-full items-center justify-between">
                    <span className="font-medium text-neutral-900 dark:text-neutral-100">
                      {selected5 || "Interview Mode"}
                    </span>
                    <div className="mr-2 rounded-md bg-neutral-100 px-2 py-1 text-xs text-neutral-700 dark:bg-neutral-800 dark:text-neutral-300">
                      Default
                    </div>
                  </div>
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="default">Interview Mode</SelectItem>
                  <SelectItem value="narrative">Narrative Style</SelectItem>
                  <SelectItem value="discussion">Panel Discussion</SelectItem>
                  <SelectItem value="monologue">Solo Monologue</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 sm:gap-6">
              <div>
                <Label className="mb-3 block text-sm font-medium text-neutral-900 dark:text-neutral-100">Host Voice</Label>
                <Select defaultValue="alex" onValueChange={setSelected2}>
                  <SelectTrigger className="h-12 w-full rounded-xl border-neutral-300 bg-white dark:border-neutral-700 dark:bg-neutral-900">
                    <div className="flex items-center gap-3">
                      <Avatar className="h-6 w-6">
                        <AvatarImage src="/voice1.png" alt="Alex" />
                      </Avatar>
                      <span className="font-medium text-neutral-900 dark:text-neutral-100">{selected2 || "alex"}</span>
                    </div>
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="alex">Alex</SelectItem>
                    <SelectItem value="sarah">Sarah</SelectItem>
                    <SelectItem value="mike">Mike</SelectItem>
                    <SelectItem value="emma">Emma</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label className="mb-3 block text-sm font-medium text-neutral-900 dark:text-neutral-100">Guest Voice</Label>
                <Select defaultValue="morgan" onValueChange={setSelected}>
                  <SelectTrigger className="h-12 w-full rounded-xl border-neutral-300 bg-white dark:border-neutral-700 dark:bg-neutral-900">
                    <div className="flex items-center gap-3">
                      <Avatar className="h-6 w-6">
                        <AvatarImage src="/voice2.png" alt="Morgan" />
                      </Avatar>
                      <span className="font-medium text-neutral-900 dark:text-neutral-100">{selected}</span>
                    </div>
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="morgan">Morgan</SelectItem>
                    <SelectItem value="jordan">Jordan</SelectItem>
                    <SelectItem value="taylor">Taylor</SelectItem>
                    <SelectItem value="casey">Casey</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 sm:gap-6">
              <div>
                <Label className="mb-3 block text-sm font-medium text-neutral-900 dark:text-neutral-100">Voice Engine</Label>
                <Select defaultValue="eleven-v2" onValueChange={setSelected3}>
                  <SelectTrigger className="h-12 w-full rounded-xl border-neutral-300 bg-white dark:border-neutral-700 dark:bg-neutral-900">
                    <div className="flex w-full items-center justify-between">
                      <span className="font-medium text-neutral-900 dark:text-neutral-100">
                        {selected3 || "Eleven AI v2"}
                      </span>
                      <div className="mr-2 rounded-md bg-neutral-100 px-2 py-1 text-xs text-neutral-700 dark:bg-neutral-800 dark:text-neutral-300">
                        Multilingual
                      </div>
                    </div>
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="eleven-v2">Eleven AI v2</SelectItem>
                    <SelectItem value="eleven-v1">Eleven AI v1</SelectItem>
                    <SelectItem value="openai">OpenAI TTS</SelectItem>
                    <SelectItem value="azure">Azure Speech</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label className="mb-3 block text-sm font-medium text-neutral-900 dark:text-neutral-100">Language</Label>
                <Select defaultValue="auto" onValueChange={setSelected4}>
                  <SelectTrigger className="h-12 w-full rounded-xl border-neutral-300 bg-white dark:border-neutral-700 dark:bg-neutral-900">
                    <span className="font-medium text-neutral-900 dark:text-neutral-100">
                      {selected4 || "Auto-detect"}
                    </span>
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="auto">Auto-detect</SelectItem>
                    <SelectItem value="english">English</SelectItem>
                    <SelectItem value="spanish">Spanish</SelectItem>
                    <SelectItem value="french">French</SelectItem>
                    <SelectItem value="german">German</SelectItem>
                    <SelectItem value="italian">Italian</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div>
              <Label className="mb-3 block text-sm font-medium text-neutral-900 dark:text-neutral-100">Audio Quality</Label>
              <Select defaultValue="studio" onValueChange={setSelected6}>
                <SelectTrigger className="h-12 w-full rounded-xl border-neutral-300 bg-white dark:border-neutral-700 dark:bg-neutral-900">
                  <span className="font-medium text-neutral-900 dark:text-neutral-100">
                    {selected6 || "Studio Quality"}
                  </span>
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="studio">Studio Quality</SelectItem>
                  <SelectItem value="high">High Quality</SelectItem>
                  <SelectItem value="standard">Standard Quality</SelectItem>
                  <SelectItem value="compressed">Compressed</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="mt-8 flex flex-col justify-end gap-3 border-t border-neutral-200 pt-6 dark:border-neutral-800 sm:flex-row sm:gap-5">
            <Button
              variant="outline"
              className="order-2 flex h-12 items-center justify-center rounded-xl border-neutral-300 bg-transparent px-4 text-sm dark:border-neutral-700 sm:order-1 sm:px-6"
            >
              <ArrowDownNarrowWide className="mr-2 h-4 w-4" />
              Recent
              <ChevronDown className="ml-2 h-4 w-4" />
            </Button>
            <Button className="order-1 h-12 rounded-xl bg-neutral-900 px-6 font-medium text-white hover:bg-neutral-800 dark:order-2 dark:bg-neutral-100 dark:text-neutral-900 dark:hover:bg-neutral-200 sm:px-8">
              Generate
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
