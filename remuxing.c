    /*
     * Copyright (c) 2013 Stefano Sabatini
     *
     * Permission is hereby granted, free of charge, to any person obtaining a copy
     * of this software and associated documentation files (the "Software"), to deal
     * in the Software without restriction, including without limitation the rights
     * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
     * copies of the Software, and to permit persons to whom the Software is
     * furnished to do so, subject to the following conditions:
     *
     * The above copyright notice and this permission notice shall be included in
     * all copies or substantial portions of the Software.
     *
     * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
     * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
     * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
     * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
     * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
     * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
     * THE SOFTWARE.
     */

    /**
     * @file
     * libavformat/libavcodec demuxing and muxing API example.
     *
     * Remux streams from one container format to another.
     * @example remuxing.c
     */

    // #include <time.h>
#include <unistd.h> // sleep
#include <libavutil/timestamp.h>
#include <libavutil/mem.h>
#include <libavformat/avformat.h>

    static void log_packet(const AVFormatContext *fmt_ctx, const AVPacket *pkt, const char *tag)
    {
	AVRational *time_base = &fmt_ctx->streams[pkt->stream_index]->time_base;

	printf("%s: pts:%s pts_time:%s dts:%s dts_time:%s duration:%s duration_time:%s stream_index:%d\n",
	       tag,
	       av_ts2str(pkt->pts), av_ts2timestr(pkt->pts, time_base),
	       av_ts2str(pkt->dts), av_ts2timestr(pkt->dts, time_base),
	       av_ts2str(pkt->duration), av_ts2timestr(pkt->duration, time_base),
	       pkt->stream_index);
    }

    int main(int argc, char **argv)
    {
	AVOutputFormat *ofmt = NULL;
	AVFormatContext *ifmt_ctx = NULL, *ofmt_ctx = NULL;
	AVPacket pkt;
	const char *in_filename, *out_filename;
	int ret, i;
	int stream_index = 0;
	int *stream_mapping = NULL;
	int stream_mapping_size = 0;
	double start = 0.0, stop = 0.0;
	int64_t last_pts,last_dts[10];
	memset(last_dts,0,sizeof(last_dts));

	if (argc < 3) {
	    printf("usage: %s input output\n"
		   "API example program to remux a media file with libavformat and libavcodec.\n"
		   "The output format is guessed according to the file extension.\n"
		   "\n", argv[0]);
	    return 1;
	}

	in_filename  = argv[1];
	out_filename = argv[2];

	if ((ret = avformat_open_input(&ifmt_ctx, in_filename, 0, 0)) < 0) {
	    printf( "Could not open input file '%s'", in_filename);
	    goto end;
	}

	if ((ret = avformat_find_stream_info(ifmt_ctx, 0)) < 0) {
	    printf( "Failed to retrieve input stream information");
	    goto end;
	}

	av_dump_format(ifmt_ctx, 0, in_filename, 0);

	avformat_alloc_output_context2(&ofmt_ctx, NULL, "mpegts", out_filename);
	if (!ofmt_ctx) {
	    printf( "Could not create output context\n");
	    ret = AVERROR_UNKNOWN;
	    goto end;
	}

	stream_mapping_size = ifmt_ctx->nb_streams;
	stream_mapping = av_malloc_array(stream_mapping_size, sizeof(*stream_mapping));
	if (!stream_mapping) {
	    ret = AVERROR(ENOMEM);
	    goto end;
	}
	memset(stream_mapping,0,stream_mapping_size*sizeof(*stream_mapping));

	ofmt = ofmt_ctx->oformat;

	for (i = 0; i < ifmt_ctx->nb_streams; i++) {
	    AVStream *out_stream;
	    AVStream *in_stream = ifmt_ctx->streams[i];
	    AVCodecParameters *in_codecpar = in_stream->codecpar;

	    if (in_codecpar->codec_type != AVMEDIA_TYPE_AUDIO &&
		in_codecpar->codec_type != AVMEDIA_TYPE_VIDEO &&
		in_codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE) {
		stream_mapping[i] = -1;
		continue;
	    }

	    stream_mapping[i] = stream_index++;

	    out_stream = avformat_new_stream(ofmt_ctx, NULL);
	    if (!out_stream) {
		printf( "Failed allocating output stream\n");
		ret = AVERROR_UNKNOWN;
		goto end;
	    }

	    ret = avcodec_parameters_copy(out_stream->codecpar, in_codecpar);
	    if (ret < 0) {
		printf( "Failed to copy codec parameters\n");
		goto end;
	    }
	    out_stream->codecpar->codec_tag = 0;
	}
	av_dump_format(ofmt_ctx, 0, out_filename, 1);

	if (!(ofmt->flags & AVFMT_NOFILE)) {
	    ret = avio_open(&ofmt_ctx->pb, out_filename, AVIO_FLAG_WRITE);
	    if (ret < 0) {
		printf( "Could not open output file '%s'", out_filename);
		goto end;
	    }
	}

	ret = avformat_write_header(ofmt_ctx, NULL);
	if (ret < 0) {
	    printf( "Error occurred when opening output file\n");
	    goto end;
	}

	while (1) {
	    AVStream *in_stream, *out_stream;

	    ret = av_read_frame(ifmt_ctx, &pkt);
	    if (ret < 0) {
		printf("stop - start %g last_pts %ld\n",stop-start,last_pts);
    tryagain:
		avformat_close_input(&ifmt_ctx);
#if 1
		sleep(1);
#else
		if (start < 1e-4) { // ??? 1st value must be guessed !
		    printf("1st sleep, forcing 5s\n");
		    sleep(5);
		} else if (stop - start > 20) {
		    printf("sleeping 7s then...\n");
		    sleep(7);
		} else if (stop - start < 9) {
		    printf("sleeping 6s then...\n");
		    sleep(6);
		} else {
		    printf("sleeping %gs\n",stop-start-3);
		    sleep(stop-start-3);
		}
#endif
		int tries = 0;
		while ((ret = avformat_open_input(&ifmt_ctx, in_filename, 0, 0)) < 0 && tries < 3) {
		    printf( "Could not open input file '%s' tries %d\n", in_filename,tries);
		    sleep(3+tries++);
		}
		if (ret < 0) goto end;
		if ((ret = avformat_find_stream_info(ifmt_ctx, 0)) < 0) {
		    printf( "Failed to retrieve input stream information");
		    goto end;
		}
		// av_dump_format(ifmt_ctx, 0, in_filename, 0);
		int nb = 0;
		do {
		    ret = av_read_frame(ifmt_ctx, &pkt);
		    nb++;
		    if (ret < 0) {
			printf("read error while trying to resync\n");
			sleep(1);
			goto tryagain;
		    }
		    // log_packet(ifmt_ctx, &pkt, "sync");
		    if (pkt.dts >= last_dts[pkt.stream_index] && pkt.pts != last_pts) {
			printf("sync: dts >= last_dts, emergency exit after %d packets !\n",nb);
			break;
		    }
		    if (pkt.pts != last_pts)
			av_packet_unref(&pkt);
		} while (pkt.pts != last_pts);
		if (ret < 0) break;
		if (pkt.pts == last_pts) {
		    ret = av_read_frame(ifmt_ctx, &pkt);
		    if (ret < 0) break;
		}
		start = stop;
		printf("resync ok start = %g\n",start);
	    }
	    // if (pkt.pts == pkt.dts) continue;
	    if (last_dts[pkt.stream_index] >= pkt.dts) {
		// printf("got dts %ld <= last_dts %ld for stream %d\n",pkt.dts,last_dts[pkt.stream_index],pkt.stream_index);
		continue;
	    }
	    in_stream  = ifmt_ctx->streams[pkt.stream_index];
	    AVRational time_base = in_stream->time_base;
	    stop = av_q2d(time_base)*pkt.pts;
	    last_pts = pkt.pts;
	    last_dts[pkt.stream_index] = pkt.dts;

	    if (pkt.stream_index >= stream_mapping_size ||
		stream_mapping[pkt.stream_index] < 0) {
		av_packet_unref(&pkt);
		continue;
	    }

	    pkt.stream_index = stream_mapping[pkt.stream_index];
	    out_stream = ofmt_ctx->streams[pkt.stream_index];
	    // log_packet(ifmt_ctx, &pkt, "in");

	    /* copy packet */
	    pkt.pts = av_rescale_q_rnd(pkt.pts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
	    pkt.dts = av_rescale_q_rnd(pkt.dts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
	    pkt.duration = av_rescale_q(pkt.duration, in_stream->time_base, out_stream->time_base);
	    pkt.pos = -1;
	    // log_packet(ofmt_ctx, &pkt, "out");

	    // ret = av_interleaved_write_frame(ofmt_ctx, &pkt);
	    ret = av_write_frame(ofmt_ctx, &pkt);
	    if (ret < 0) {
		printf( "Error muxing packet\n");
		break;
	    }
	    av_packet_unref(&pkt);
	}

	av_write_trailer(ofmt_ctx);
    end:

	avformat_close_input(&ifmt_ctx);

	/* close output */
	if (ofmt_ctx && !(ofmt->flags & AVFMT_NOFILE))
	    avio_closep(&ofmt_ctx->pb);
	avformat_free_context(ofmt_ctx);

	av_freep(&stream_mapping);

	if (ret < 0 && ret != AVERROR_EOF) {
	    printf( "Error occurred: %s\n", av_err2str(ret));
	    return 1;
	}

	return 0;
    }
