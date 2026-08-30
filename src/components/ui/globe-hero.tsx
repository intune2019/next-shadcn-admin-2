"use client";

import { Canvas, useFrame } from "@react-three/fiber";
import { PerspectiveCamera } from "@react-three/drei";
import { motion } from "framer-motion";
import Link from "next/link";
import React, { useRef } from "react";
import * as THREE from "three";

import { ArrowRight, Zap } from "lucide-react";

import { cn } from "@/lib/utils";

interface DotGlobeHeroProps {
  rotationSpeed?: number;
  globeRadius?: number;
  className?: string;
  children?: React.ReactNode;
}

const Globe: React.FC<{
  rotationSpeed: number;
  radius: number;
}> = ({ rotationSpeed, radius }) => {
  const groupRef = useRef<THREE.Group>(null!);

  useFrame(() => {
    if (groupRef.current) {
      groupRef.current.rotation.y += rotationSpeed;
      groupRef.current.rotation.x += rotationSpeed * 0.3;
      groupRef.current.rotation.z += rotationSpeed * 0.1;
    }
  });

  return (
    <group ref={groupRef}>
      <mesh>
        <sphereGeometry args={[radius, 64, 64]} />
        <meshBasicMaterial color="var(--foreground)" transparent opacity={0.15} wireframe />
      </mesh>
    </group>
  );
};

const MotionLink = motion(Link);

const DotGlobeHero = React.forwardRef<HTMLDivElement, DotGlobeHeroProps>(
  ({ rotationSpeed = 0.005, globeRadius = 1, className, children, ...props }, ref) => {
    return (
      <div ref={ref} className={cn("relative h-screen w-full overflow-hidden bg-background", className)} {...props}>
        <div className="relative z-10 flex h-full flex-col items-center justify-center">{children}</div>

        <div className="pointer-events-none absolute inset-0 z-0">
          <Canvas>
            <PerspectiveCamera makeDefault position={[0, 0, 3]} fov={75} />
            <ambientLight intensity={0.5} />
            <pointLight position={[10, 10, 10]} intensity={1} />
            <Globe rotationSpeed={rotationSpeed} radius={globeRadius} />
          </Canvas>
        </div>
      </div>
    );
  },
);

DotGlobeHero.displayName = "DotGlobeHero";

function DotGlobeHeroDemo() {
  return (
    <DotGlobeHero
      rotationSpeed={0.004}
      className="relative overflow-hidden bg-linear-to-br from-background via-background/95 to-muted/10"
    >
      <div className="pointer-events-none absolute inset-0 bg-linear-to-t from-background/50 via-transparent to-background/30" />
      <div className="pointer-events-none absolute top-1/4 left-1/4 size-96 rounded-full bg-primary/5 blur-3xl motion-safe:animate-pulse" />
      <div className="pointer-events-none absolute right-1/4 bottom-1/4 size-64 rounded-full bg-primary/3 blur-3xl motion-safe:animate-pulse" />

      <div className="relative z-10 mx-auto max-w-5xl space-y-12 px-6 py-12 text-center">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8 }}
          className="space-y-8"
        >
          <motion.div
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.6, delay: 0.2 }}
            className="relative inline-flex items-center gap-3 rounded-full border border-primary/30 bg-linear-to-r from-primary/20 via-primary/10 to-primary/20 px-6 py-3 shadow-2xl backdrop-blur-xl"
          >
            <div className="absolute inset-0 rounded-full bg-linear-to-r from-primary/10 via-transparent to-primary/10 motion-safe:animate-pulse" />
            <div className="size-2 rounded-full bg-primary motion-safe:animate-ping" />
            <span className="relative z-10 font-bold text-primary text-sm uppercase tracking-wider">GLOBAL NETWORK</span>
            <div className="size-2 rounded-full bg-primary motion-safe:animate-ping" />
          </motion.div>

          <div className="space-y-6">
            <motion.h1
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 1, delay: 0.3 }}
              className="select-none text-5xl font-black leading-[0.85] tracking-tighter md:text-7xl lg:text-8xl xl:text-9xl"
            >
              <span className="mb-3 block font-light text-4xl text-foreground/70 md:text-6xl lg:text-7xl">Connect</span>
              <span className="relative block">
                <span className="relative z-10 bg-linear-to-br from-primary via-primary to-primary/60 bg-clip-text font-black text-transparent">
                  the World
                </span>
                <span className="absolute inset-0 scale-105 bg-linear-to-br from-primary via-primary to-primary/60 bg-clip-text font-black text-transparent opacity-50 blur-2xl">
                  the World
                </span>
                <motion.span
                  initial={{ width: 0 }}
                  animate={{ width: "100%" }}
                  transition={{ duration: 1.5, delay: 1.2, ease: "easeOut" }}
                  className="absolute -bottom-6 left-0 h-3 rounded-full bg-linear-to-r from-primary via-primary/80 to-transparent shadow-lg shadow-primary/50"
                />
              </span>
            </motion.h1>
          </div>

          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.8, delay: 0.8 }}
            className="mx-auto max-w-3xl space-y-4"
          >
            <p className="font-medium text-muted-foreground text-xl leading-relaxed md:text-2xl">
              Experience real-time global connectivity with our{" "}
              <span className="rounded-md bg-linear-to-r from-primary/20 to-primary/10 px-2 py-1 font-semibold text-foreground">
                distributed network infrastructure
              </span>
            </p>
            <p className="text-lg text-muted-foreground/80 leading-relaxed">
              Monitor data flows, track performance, and scale across continents with unprecedented reliability.
            </p>
          </motion.div>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 1 }}
          className="flex flex-col items-center justify-center gap-6 pt-4 sm:flex-row"
        >
          <MotionLink
            href="#capabilities"
            whileHover={{ scale: 1.05, boxShadow: "0 20px 40px rgba(0,0,0,0.2), 0 0 25px var(--primary)", y: -2 }}
            whileTap={{ scale: 0.98 }}
            className="group relative inline-flex items-center gap-3 overflow-hidden rounded-xl border border-primary/20 bg-linear-to-r from-primary via-primary to-primary/90 px-8 py-4 font-semibold text-lg text-primary-foreground shadow-xl transition-all duration-500 hover:shadow-primary/30"
          >
            <span className="relative z-10 tracking-wide">Start Exploring</span>
            <ArrowRight className="relative z-10 size-5 transition-transform duration-300 group-hover:translate-x-2" />
          </MotionLink>

          <MotionLink
            href="/dashboard/default"
            whileHover={{
              scale: 1.05,
              backgroundColor: "var(--accent)",
              borderColor: "var(--primary)",
              boxShadow: "0 15px 30px rgba(0,0,0,0.1), 0 0 15px var(--primary)",
              y: -2,
            }}
            whileTap={{ scale: 0.98 }}
            className="group relative inline-flex items-center gap-3 overflow-hidden rounded-xl border-2 border-border/40 bg-background/60 px-8 py-4 font-semibold text-lg transition-all duration-500 hover:border-primary/40 hover:bg-background/90 shadow-lg backdrop-blur-xl"
          >
            <div className="absolute inset-0 bg-linear-to-r from-primary/5 via-transparent to-primary/5 opacity-0 transition-opacity duration-500 group-hover:opacity-100" />
            <Zap className="relative z-10 size-5 transition-all duration-300 group-hover:rotate-6 group-hover:scale-110" />
            <span className="relative z-10 tracking-wide">View Live Demo</span>
          </MotionLink>
        </motion.div>
      </div>
    </DotGlobeHero>
  );
}

export { DotGlobeHero, DotGlobeHeroDemo, type DotGlobeHeroProps };
