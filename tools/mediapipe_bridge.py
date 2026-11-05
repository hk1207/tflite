#!/usr/bin/env python3
"""MediaPipe pose bridge for PoseMotion.

Runs the MediaPipe Pose Landmarker (Python) on a webcam, a video or an image and
sends the landmarks to PoseMotion as text lines over UDP (127.0.0.1:5005 by
default). In PoseMotion choose "MediaPipe (Python bridge)" as the pose model.

The bridge opens the camera itself, so PoseMotion doesn't use its own camera in
this mode (a webcam can only be opened by one program).

Setup:
    pip install mediapipe opencv-python
    Download pose_landmarker_full.task (or lite / heavy) from
    https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker#models

Usage:
    python mediapipe_bridge.py --model pose_landmarker_full.task            # webcam 0
    python mediapipe_bridge.py --model pose_landmarker_full.task --camera 1
    python mediapipe_bridge.py --model pose_landmarker_full.task --video dance.mp4
    python mediapipe_bridge.py --model pose_landmarker_full.task --image person.jpg
    python mediapipe_bridge.py --selftest                                   # prints one line, no MediaPipe

Protocol (one line per frame, numbers with a dot):
    MP1 <width> <height> <found 0/1> [33 x (x y z visibility)  33 x (wx wy wz)]
x, y are 0..1 relative to the frame. wx, wy, wz are the world landmarks in
meters (MediaPipe axes : x right, y down, z away from the camera).
"""
import argparse
import socket
import sys
import time

LANDMARKS = 33


def format_line(width, height, landmarks, world):
    """landmarks : 33 items (x, y, z, visibility); world : 33 items (x, y, z). None = no pose."""
    if landmarks is None or world is None:
        return "MP1 %d %d 0" % (width, height)
    parts = ["MP1", str(width), str(height), "1"]
    for x, y, z, v in landmarks:
        parts.append("%.5f %.5f %.5f %.4f" % (x, y, z, v))
    for x, y, z in world:
        parts.append("%.5f %.5f %.5f" % (x, y, z))
    return " ".join(parts)


def selftest_pose():
    """A synthetic standing pose (for --selftest and the tests of the Pascal parser)."""
    lm = [(0.5, 0.5, 0.0, 0.99)] * LANDMARKS
    world = [(0.0, 0.0, 0.0)] * LANDMARKS
    lm = list(lm)
    world = list(world)
    lm[0] = (0.50, 0.20, -0.1, 0.99)        # nose
    lm[11] = (0.60, 0.30, 0.0, 0.98)        # left shoulder (image right)
    lm[12] = (0.40, 0.30, 0.0, 0.97)        # right shoulder
    world[0] = (0.0, -0.60, -0.10)
    world[11] = (0.20, -0.45, 0.05)
    world[12] = (-0.20, -0.45, -0.05)
    return lm, world


def run_mediapipe(args):
    import cv2
    import mediapipe as mp
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    target = (args.host, args.port)

    mode = vision.RunningMode.IMAGE if args.image else vision.RunningMode.VIDEO
    options = vision.PoseLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=args.model),
        running_mode=mode, num_poses=1)
    landmarker = vision.PoseLandmarker.create_from_options(options)

    def process(frame_bgr, timestamp_ms):
        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        if mode == vision.RunningMode.IMAGE:
            result = landmarker.detect(image)
        else:
            result = landmarker.detect_for_video(image, timestamp_ms)
        h, w = frame_bgr.shape[:2]
        if result.pose_landmarks and result.pose_world_landmarks:
            lm = [(p.x, p.y, p.z, p.visibility if p.visibility is not None else 1.0)
                  for p in result.pose_landmarks[0]]
            wl = [(p.x, p.y, p.z) for p in result.pose_world_landmarks[0]]
            line = format_line(w, h, lm, wl)
        else:
            line = format_line(w, h, None, None)
        sock.sendto(line.encode("ascii"), target)
        if args.preview:
            if result.pose_landmarks:
                for p in result.pose_landmarks[0]:
                    cv2.circle(frame_bgr, (int(p.x * w), int(p.y * h)), 3, (0, 255, 0), -1)
            cv2.imshow("MediaPipe bridge (q = quit)", frame_bgr)

    if args.image:
        frame = cv2.imread(args.image)
        if frame is None:
            sys.exit("Cannot read " + args.image)
        while True:  # send the same image again and again
            process(frame, 0)
            if args.preview and (cv2.waitKey(33) & 0xFF) == ord("q"):
                break
            time.sleep(0.033)
        return

    capture = cv2.VideoCapture(args.video if args.video else args.camera)
    if not capture.isOpened():
        sys.exit("Cannot open the video source")
    start = time.time()
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        process(frame, int((time.time() - start) * 1000))
        if args.preview and (cv2.waitKey(1) & 0xFF) == ord("q"):
            break
    capture.release()


def main():
    parser = argparse.ArgumentParser(description="MediaPipe pose bridge for PoseMotion")
    parser.add_argument("--model", help="pose_landmarker_*.task file")
    parser.add_argument("--camera", type=int, default=0, help="camera index (default 0)")
    parser.add_argument("--video", help="video file instead of the camera")
    parser.add_argument("--image", help="image file instead of the camera")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5005)
    parser.add_argument("--preview", action="store_true", help="show the camera image with the landmarks")
    parser.add_argument("--selftest", action="store_true", help="print one synthetic line and exit")
    args = parser.parse_args()

    if args.selftest:
        lm, world = selftest_pose()
        print(format_line(640, 480, lm, world))
        return
    if not args.model:
        parser.error("--model is required")
    run_mediapipe(args)


if __name__ == "__main__":
    main()
