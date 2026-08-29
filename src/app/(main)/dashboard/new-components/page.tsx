import { Globe, Search } from "lucide-react";

import { GlobeCdn } from "@/components/ui/cobe-globe-cdn";
import BasicSteps from "@/components/ui/basic-steps";
import { DateRangeCalendarDemo } from "@/components/ui/date-range-calendar";
import { DropdownNavigationDemo } from "@/components/ui/dropdown-navigation-demo";
import FileUpload from "@/components/ui/file-upload";
import GanttDemo from "@/components/ui/gantt-demo";
import FileUpload01 from "@/components/ui/file-upload-01";
import FormLayout02 from "@/components/ui/form-1";
import InputModel from "@/components/ui/input-model";
import { OrderTrackingDemo } from "@/components/ui/order-tracking-demo";
import SignupForm from "@/components/ui/login-signup";
import StepsWithNavigation from "@/components/ui/steps-with-navigation";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";

export default function Page() {
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-2">
        <Globe className="size-5" />
        <h1 className="text-3xl tracking-tight">New Components</h1>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Search input</CardTitle>
            <CardDescription>A compact input field for filtering component collections.</CardDescription>
          </CardHeader>
          <CardContent className="flex min-h-32 items-center">
            <InputGroup>
              <InputGroupAddon>
                <Search />
              </InputGroupAddon>
              <InputGroupInput aria-label="Search components" placeholder="Search components..." />
            </InputGroup>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>CDN globe</CardTitle>
            <CardDescription>Interactive globe with live traffic markers and network arcs.</CardDescription>
          </CardHeader>
          <CardContent className="flex items-center justify-center bg-white p-4 dark:bg-white">
            <GlobeCdn className="w-full max-w-sm" />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Audio show creator</CardTitle>
            <CardDescription>Modal-style content creation flow with upload, URL, and voice controls.</CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            <InputModel />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>File upload</CardTitle>
            <CardDescription>Drag-and-drop uploader with selected file details and removal controls.</CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            <FileUpload />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Settings form</CardTitle>
            <CardDescription>Responsive account, workspace, and notification settings form.</CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            <FormLayout02 />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Signup form</CardTitle>
            <CardDescription>Account creation form with role selection and password visibility control.</CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            <SignupForm />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Date range picker</CardTitle>
            <CardDescription>Interactive calendar with date range selection, time inputs, and timezone controls.</CardDescription>
          </CardHeader>
          <CardContent className="flex justify-center p-0">
            <DateRangeCalendarDemo />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Project image upload</CardTitle>
            <CardDescription>Create a project with a lead, image upload, progress indicator, and help tooltip.</CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            <FileUpload01 />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Gantt roadmap</CardTitle>
            <CardDescription>Drag feature timelines, browse grouped issues, and manage roadmap markers.</CardDescription>
          </CardHeader>
          <CardContent className="overflow-hidden p-0">
            <GanttDemo />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Order tracking</CardTitle>
            <CardDescription>Vertical delivery progress indicator with completed and pending steps.</CardDescription>
          </CardHeader>
          <CardContent className="flex justify-center">
            <OrderTrackingDemo />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Dropdown navigation</CardTitle>
            <CardDescription>Hover navigation with animated menu transitions and grouped links.</CardDescription>
          </CardHeader>
          <CardContent className="overflow-hidden p-0">
            <DropdownNavigationDemo />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Basic steps</CardTitle>
            <CardDescription>Numbered progress indicator for a simple multi-step flow.</CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            <BasicSteps />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Steps with navigation</CardTitle>
            <CardDescription>Interactive step progress indicator with previous and next controls.</CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            <StepsWithNavigation />
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
