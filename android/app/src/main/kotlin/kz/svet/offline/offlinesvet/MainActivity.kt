package kz.svet.offline.offlinesvet

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Сжатие записи разговора WAV → M4A (AAC) для вложения в Битрикс24.
        // Встроенный кодировщик Android, без сторонних библиотек.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kz.svet.offline/audio")
            .setMethodCallHandler { call, result ->
                if (call.method != "wavToM4a") { result.notImplemented(); return@setMethodCallHandler }
                val input = call.argument<String>("input")!!
                val output = call.argument<String>("output")!!
                val bitrate = call.argument<Int>("bitrate") ?: 64000
                Thread {
                    try {
                        WavToM4a.convert(input, output, bitrate)
                        runOnUiThread { result.success(output) }
                    } catch (e: Exception) {
                        File(output).delete()
                        runOnUiThread { result.error("CONVERT_FAILED", e.message, null) }
                    }
                }.start()
            }
    }
}

object WavToM4a {
    private class WavInfo(val channels: Int, val sampleRate: Int, val bits: Int, val dataOffset: Long, val dataSize: Long)

    private fun readWav(raf: RandomAccessFile): WavInfo {
        val header = ByteArray(12)
        raf.readFully(header)
        if (String(header, 0, 4) != "RIFF" || String(header, 8, 4) != "WAVE") throw IllegalArgumentException("Не WAV")
        var channels = 1; var sampleRate = 48000; var bits = 16
        while (raf.filePointer < raf.length()) {
            val chunk = ByteArray(8)
            raf.readFully(chunk)
            val id = String(chunk, 0, 4)
            val size = ByteBuffer.wrap(chunk, 4, 4).order(ByteOrder.LITTLE_ENDIAN).int.toLong() and 0xFFFFFFFFL
            if (id == "fmt ") {
                val fmt = ByteArray(size.toInt())
                raf.readFully(fmt)
                val b = ByteBuffer.wrap(fmt).order(ByteOrder.LITTLE_ENDIAN)
                channels = b.getShort(2).toInt()
                sampleRate = b.getInt(4)
                bits = b.getShort(14).toInt()
            } else if (id == "data") {
                // Запись могла остановиться без обновления размера — берём до конца файла.
                val real = raf.length() - raf.filePointer
                val dataSize = if (size == 0L || size > real) real else size
                return WavInfo(channels, sampleRate, bits, raf.filePointer, dataSize)
            } else {
                raf.seek(raf.filePointer + size + (size and 1))
            }
        }
        throw IllegalArgumentException("Нет блока data")
    }

    fun convert(inputPath: String, outputPath: String, bitrate: Int) {
        RandomAccessFile(inputPath, "r").use { raf ->
            val wav = readWav(raf)
            if (wav.bits != 16) throw IllegalArgumentException("Поддерживается только 16 бит")
            raf.seek(wav.dataOffset)

            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, wav.sampleRate, wav.channels).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
            }
            val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            var track = -1
            var muxerStarted = false
            val info = MediaCodec.BufferInfo()
            val bytesPerFrame = 2 * wav.channels
            var remaining = wav.dataSize
            var framesRead = 0L
            var inputDone = false
            var outputDone = false
            val chunk = ByteArray(8192 - (8192 % bytesPerFrame))

            try {
                while (!outputDone) {
                    if (!inputDone) {
                        val inIndex = codec.dequeueInputBuffer(10000)
                        if (inIndex >= 0) {
                            val buf = codec.getInputBuffer(inIndex)!!
                            buf.clear()
                            val want = minOf(chunk.size.toLong(), remaining, buf.capacity().toLong()).toInt()
                            val read = if (want > 0) raf.read(chunk, 0, want) else -1
                            val pts = framesRead * 1_000_000L / wav.sampleRate
                            if (read <= 0) {
                                codec.queueInputBuffer(inIndex, 0, 0, pts, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                buf.put(chunk, 0, read)
                                codec.queueInputBuffer(inIndex, 0, read, pts, 0)
                                remaining -= read
                                framesRead += read / bytesPerFrame
                            }
                        }
                    }
                    val outIndex = codec.dequeueOutputBuffer(info, 10000)
                    when {
                        outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            track = muxer.addTrack(codec.outputFormat)
                            muxer.start()
                            muxerStarted = true
                        }
                        outIndex >= 0 -> {
                            val out = codec.getOutputBuffer(outIndex)!!
                            if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                            if (info.size > 0 && muxerStarted) {
                                out.position(info.offset)
                                out.limit(info.offset + info.size)
                                muxer.writeSampleData(track, out, info)
                            }
                            codec.releaseOutputBuffer(outIndex, false)
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                        }
                    }
                }
            } finally {
                codec.stop(); codec.release()
                if (muxerStarted) muxer.stop()
                muxer.release()
            }
        }
    }
}
