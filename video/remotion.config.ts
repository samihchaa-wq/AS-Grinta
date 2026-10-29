import {Config} from '@remotion/cli/config';

// Rendu destiné aux navigateurs mobiles : H.264, pixels 4:2:0.
Config.setVideoImageFormat('jpeg');
Config.setCodec('h264');
Config.setPixelFormat('yuv420p');
