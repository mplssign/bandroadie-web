/**
 * BandRoadie Splash Screen
 * Displays the splash image, then calls onComplete.
 *
 * Usage:
 *   import SplashScreen from "./SplashScreen";
 *   <SplashScreen onComplete={() => navigate("/dashboard")} />
 *
 * Props:
 *   onComplete  () => void   Called when the splash finishes (route to dashboard here)
 *   duration    number       How long (ms) to show the splash before calling onComplete (default: 2500)
 */
import { useEffect } from "react";
import splashImage from "../assets/images/splash.png";

export default function SplashScreen({ onComplete = () => {}, duration = 2500 }) {
  useEffect(() => {
    const timer = setTimeout(onComplete, duration);
    return () => clearTimeout(timer);
  }, [onComplete, duration]);

  return (
    <div style={S.root}>
      <img
        src={splashImage}
        alt="BandRoadie"
        style={S.image}
        draggable={false}
      />
    </div>
  );
}

const S = {
  root: {
    position:       "fixed",
    inset:          0,
    background:     "#0e0e0e",
    display:        "flex",
    alignItems:     "center",
    justifyContent: "center",
    overflow:       "hidden",
  },
  image: {
    width:         "100%",
    height:        "100%",
    objectFit:     "contain",
    userSelect:    "none",
    pointerEvents: "none",
  },
};
