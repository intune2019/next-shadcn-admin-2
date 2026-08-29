"use client";

export default function BasicSteps() {
  const steps = [1, 2, 3, 4];
  const currentStep = 1;

  return (
    <div className="flex w-full items-center justify-center rounded-xl bg-white px-4 py-12 dark:bg-gray-800">
      <div className="w-full max-w-2xl">
        <div className="flex items-center justify-between">
          {steps.map((step, index) => (
            <div key={step} className="relative flex flex-1 items-center last:flex-none">
              <div className="flex items-center gap-3 rounded-md text-left">
                <div
                  className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full border-2 text-sm font-semibold ${
                    index < currentStep
                      ? "border-blue-600 bg-blue-600 text-white"
                      : index === currentStep
                        ? "border-blue-600 bg-blue-600 text-white"
                        : "border-gray-200 bg-gray-100 text-gray-500 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-300"
                  }`}
                >
                  {step}
                </div>
              </div>
              {index < steps.length - 1 && (
                <div
                  className={`mx-3 h-0.5 flex-1 ${
                    index < currentStep ? "bg-blue-600" : "bg-gray-200 dark:bg-gray-700"
                  }`}
                />
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
