#!/usr/bin/env python3
"""Virtual gamepad on the MiSTer via /dev/uinput, pure ctypes -- no evdev.

Impersonates the Xbox 360 pad already present (045e:028e) so MiSTer applies the
existing input_045e_028e_v3.map instead of treating it as a new device.

usage: vjoy.py <btn> [hold_s]     btn in: a b x y start select up down left right
"""
import ctypes, fcntl, os, struct, sys, time

UI_SET_EVBIT=0x40045564; UI_SET_KEYBIT=0x40045565; UI_SET_ABSBIT=0x40045567
UI_DEV_CREATE=0x5501; UI_DEV_DESTROY=0x5502
EV_SYN,EV_KEY,EV_ABS=0x00,0x01,0x03
BTN={'a':0x130,'b':0x131,'x':0x133,'y':0x134,'select':0x13a,'start':0x13b,
     'tl':0x136,'tr':0x137}
HAT={'left':(0x10,-1),'right':(0x10,1),'up':(0x11,-1),'down':(0x11,1)}

fd=os.open('/dev/uinput', os.O_WRONLY|os.O_NONBLOCK)
fcntl.ioctl(fd,UI_SET_EVBIT,EV_KEY); fcntl.ioctl(fd,UI_SET_EVBIT,EV_ABS)
fcntl.ioctl(fd,UI_SET_EVBIT,EV_SYN)
for c in BTN.values(): fcntl.ioctl(fd,UI_SET_KEYBIT,c)
for a in (0x00,0x01,0x10,0x11): fcntl.ioctl(fd,UI_SET_ABSBIT,a)

# struct uinput_user_dev: char name[80]; struct input_id {u16 x4}; u32 ff; then
# absmax/absmin/absfuzz/absflat, 64 s32 each
name=b'MiSTer vjoy'+b'\0'*(80-11)
dev=name+struct.pack('<HHHH',3,0x045e,0x028e,0x0110)+struct.pack('<I',0)
amax=[0]*64; amin=[0]*64
for a in (0x00,0x01): amax[a]=32767; amin[a]=-32768
for a in (0x10,0x11): amax[a]=1; amin[a]=-1
dev+=struct.pack('<64i',*amax)+struct.pack('<64i',*amin)
dev+=struct.pack('<64i',*([0]*64))+struct.pack('<64i',*([0]*64))
os.write(fd,dev); fcntl.ioctl(fd,UI_DEV_CREATE)
time.sleep(1.0)                      # let MiSTer enumerate it

def ev(t,c,v):
    os.write(fd,struct.pack('<llHHi',0,0,t,c,v))
def syn(): ev(EV_SYN,0,0)

btn=sys.argv[1].lower(); hold=float(sys.argv[2]) if len(sys.argv)>2 else 0.25
if btn in BTN:   ev(EV_KEY,BTN[btn],1); syn(); time.sleep(hold); ev(EV_KEY,BTN[btn],0); syn()
elif btn in HAT: a,v=HAT[btn]; ev(EV_ABS,a,v); syn(); time.sleep(hold); ev(EV_ABS,a,0); syn()
else: print("unknown button",btn); 
time.sleep(0.3)
fcntl.ioctl(fd,UI_DEV_DESTROY); os.close(fd)
print("sent",btn)
