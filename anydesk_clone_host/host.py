import asyncio
import websockets
import json
import pyautogui

# Disable pyautogui failsafe for this prototype (so it doesn't crash if mouse hits corner)
pyautogui.FAILSAFE = False

async def handler(websocket):
    print("Flutter App connected to Python Host script.")
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                action = data.get("action")
                
                if action == "move":
                    # Get normalized coordinates (0.0 to 1.0)
                    nx = data.get("x", 0)
                    ny = data.get("y", 0)
                    
                    # Get screen size
                    screen_width, screen_height = pyautogui.size()
                    
                    # Scale to actual screen
                    x = int(nx * screen_width)
                    y = int(ny * screen_height)
                    
                    pyautogui.moveTo(x, y)
                    print(f"Moved mouse to {x}, {y} (scaled from {nx}, {ny})")
                elif action == "click":
                    pyautogui.click()
                    print("Mouse clicked")
                elif action == "scroll":
                    amount = data.get("amount", 0)
                    pyautogui.scroll(amount)
                    print(f"Scrolled {amount}")
                elif action == "type":
                    text = data.get("text", "")
                    pyautogui.write(text)
                    print(f"Typed: {text}")
            except Exception as e:
                print(f"Error parsing message: {e}")
    except websockets.exceptions.ConnectionClosed:
        print("Connection closed.")

async def main():
    print("Starting Python OS Control Receiver on ws://localhost:8081...")
    async with websockets.serve(handler, "localhost", 8081):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
