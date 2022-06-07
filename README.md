用Apple原生实现音视频的采集，音频的硬编码AAC，视频的编码H264和视频的解码YUV。

本Demo在Mac上进行开发，但是iOS的采集和编码的库是通用的，可以无缝衔接。

*关于单独使用ffmpeg 进行编解码的demo可以参考 [这个工程](https://github.com/goldWave/QTFFmpegDemo)*

# 主要使用
- `AudioQueue` 采集音频
- `AVCaptureSession` 采集音频
- `AVCaptureSession` 采集视频
- `AudioToolbox` 的 `AudioConverter` 对PCM音频 进行 硬编码成  AAC
- `VideoToolbox` 的 `VTCompressionSession` 对原始YUV视频数据 进行 硬编码成 H264
- `VideoToolbox` 的 `VTDecompressionSession` 对H264视频数据 进行 硬解码成 RGBA的 `CVImageBufferRef` 格式进行界面展示

# 程序预览界面展示如下
![预览界面展示如下](https://github.com/goldWave/AudioVideoStudy/blob/main/JBMacAVDemo/Snipaste_preview.png)

# 停止采集编码后，控制台会输出本次，生成的文件路径，和使用ffmpeg进行预览的命令行
![图片](https://github.com/goldWave/AudioVideoStudy/blob/main/JBMacAVDemo/Snipaste_output.png)