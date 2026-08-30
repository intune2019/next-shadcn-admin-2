"use client";

import { useState } from "react";
import { Check } from "lucide-react";

export default function StepsWithNavigation() {
  const steps = [1, 2, 3, 4];
  const [currentStep, setCurrentStep] = useState(2);

  return (
    <div className="flex w-full items-center justify-center rounded-xl bg-white px-4 py-12 dark:bg-gray-800">
      <div className="w-full max-w-2xl space-y-6">
        <div className="flex items-center justify-between">
          {steps.map((step, index) => {
            const isComplete = index < currentStep;
            const isCurrent = index === currentStep;

            return (
              <div key={step} className="relative flex flex-1 items-center last:flex-none">
                <button
                  type="button"
                  className="group flex cursor-default items-center gap-3 rounded-md text-left"
                  disabled
                >
                  <div
                    className={`relative flex h-8 w-8 shrink-0 items-center justify-center rounded-full border-2 text-sm font-semibold ${
                      isComplete || isCurrent
                        ? "border-blue-600 bg-blue-600 text-white"
                        : "border-gray-200 bg-gray-100 text-gray-500 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-300"
                    }`}
                  >
                    <span className={isComplete ? "hidden" : "group-data-complete:hidden"}>{step}</span>
                    {isComplete && <Check className="h-4 w-4" />}
                  </div>
                </button>
                {index < steps.length - 1 && (
                  <div
                    className={`mx-3 h-0.5 flex-1 ${
                      index < currentStep ? "bg-blue-600" : "bg-gray-200 dark:bg-gray-700"
                    }`}
                  />
                )}
              </div>
            );
          })}
        </div>

        <div className="mt-8 flex justify-center gap-3">
          <button
            type="button"
            className="rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700"
            onClick={() => setCurrentStep((step) => Math.max(0, step - 1))}
            disabled={currentStep === 0}
          >
            Prev step
          </button>
          <button
            type="button"
            className="rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700"
            onClick={() => setCurrentStep((step) => Math.min(steps.length - 1, step + 1))}
            disabled={currentStep === steps.length - 1}
          >
            Next step
          </button>
        </div>
      </div>
    </div>
  );
}
