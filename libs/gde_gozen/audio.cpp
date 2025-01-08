#include "audio.hpp"
#include <map>


PackedByteArray Audio::get_audio_data(String a_path) {
	av_log_set_level(AV_LOG_VERBOSE);
	AVFormatContext *l_format_ctx = avformat_alloc_context();
	PackedByteArray l_data = PackedByteArray();

	if (!l_format_ctx) {
		_log_err("Couldn't create AV Format");
		return l_data;
	}

	if (avformat_open_input(&l_format_ctx, a_path.utf8(), NULL, NULL)) {
		_log_err("Couldn't open audio");
		return l_data;
	}

	if (avformat_find_stream_info(l_format_ctx, NULL)) {
		_log_err("Couldn't find stream info");
		return l_data;
	}

	for (int i = 0; i < l_format_ctx->nb_streams; i++) {
		AVCodecParameters *av_codec_params = l_format_ctx->streams[i]->codecpar;

		if (!avcodec_find_decoder(av_codec_params->codec_id)) {
			l_format_ctx->streams[i]->discard = AVDISCARD_ALL;
			continue;
		} else if (av_codec_params->codec_type == AVMEDIA_TYPE_AUDIO) {
			l_data = _get_audio(l_format_ctx, l_format_ctx->streams[i]);
			break;
		}
	}

	avformat_close_input(&l_format_ctx);
	av_log_set_level(AV_LOG_INFO);
	return l_data;
}


PackedByteArray Audio::combine_data(PackedByteArray a_one, PackedByteArray a_two) {
	const int16_t *l_one = (const int16_t*)a_one.ptr();
	const int16_t *l_two = (const int16_t*)a_two.ptr();

	for (size_t i = 0; i < a_one.size() / 2; i++)
        ((int16_t*)a_one.ptrw())[i] = Math::clamp(l_one[i] + l_two[i], -32768, 32767);

    return a_one;
}


PackedByteArray Audio::change_db(PackedByteArray a_data, float a_db) {
	static std::map<int, double> l_cache;

	const int16_t *l_data = (const int16_t*)a_data.ptr();
	const auto l_search = l_cache.find(a_db);
	double l_value;

	if (l_search == l_cache.end()) {
		l_value = std::pow(10.0, a_db / 20.0);
		l_cache[a_db] = l_value;
	} else l_value = l_search->second;
	
	for (size_t i = 0; i < a_data.size() / 2; i++)
		((int16_t*)a_data.ptrw())[i] = Math::clamp((int32_t)(l_data[i] * l_value), -32768, 32767);

    return a_data;
}


PackedByteArray Audio::change_to_mono(PackedByteArray a_data, bool a_left) {
	const int16_t *l_data = (const int16_t*)a_data.ptr();

	if (a_left) {
		for (size_t i = 0; i < a_data.size() / 2; i += 2)
			((int16_t*)a_data.ptrw())[i + 1] = l_data[i];
    } else {
		for (size_t i = 0; i < a_data.size() / 2; i += 2)
			((int16_t*)a_data.ptrw())[i] = l_data[i + 1];
	}

    return a_data;
}


PackedByteArray Audio::_get_audio(AVFormatContext *&a_format_ctx, AVStream *&a_stream) {
	const int TARGET_SAMPLE_RATE = 44100;
	const AVSampleFormat TARGET_FORMAT = AV_SAMPLE_FMT_S16;
	const AVChannelLayout TARGET_LAYOUT = AV_CHANNEL_LAYOUT_STEREO;

	struct SwrContext *l_swr_ctx = nullptr;
	PackedByteArray l_data = PackedByteArray();


	const AVCodec *l_codec_audio = avcodec_find_decoder(a_stream->codecpar->codec_id);
	if (!l_codec_audio) {
		UtilityFunctions::printerr("Couldn't find any codec decoder for audio!");
		return l_data;
	}

	AVCodecContext *l_codec_ctx_audio = avcodec_alloc_context3(l_codec_audio);
	if (l_codec_ctx_audio == NULL) {
		UtilityFunctions::printerr("Couldn't allocate codec context for audio!");
		return l_data;
	} else if (avcodec_parameters_to_context(l_codec_ctx_audio, a_stream->codecpar)) {
		UtilityFunctions::printerr("Couldn't initialize audio codec context!");
		return l_data;
	}

	enable_multithreading(l_codec_ctx_audio, l_codec_audio);
	l_codec_ctx_audio->request_sample_fmt = TARGET_FORMAT;

	if (avcodec_open2(l_codec_ctx_audio, l_codec_audio, NULL)) {
		UtilityFunctions::printerr("Couldn't open audio codec!");
		return l_data;
	}

	response = swr_alloc_set_opts2(&l_swr_ctx,
			&TARGET_LAYOUT,		// Out channel layout: Stereo
			TARGET_FORMAT,		// We need 16 bits
			TARGET_SAMPLE_RATE,	// Sample rate should be the Godot default
			&l_codec_ctx_audio->ch_layout,  // In channel layout
			l_codec_ctx_audio->sample_fmt,	// In sample format
			l_codec_ctx_audio->sample_rate, // In sample rate
			0, nullptr);
	if (response < 0 || (response = swr_init(l_swr_ctx))) {
		print_av_error("Couldn't initialize SWR!", response);
		avcodec_flush_buffers(l_codec_ctx_audio);
		avcodec_free_context(&l_codec_ctx_audio);
		return l_data;
	}

	AVFrame *l_frame = av_frame_alloc(), *l_decoded_frame = av_frame_alloc();
	AVPacket *l_packet = av_packet_alloc();
	if (!l_frame || !l_decoded_frame || !l_packet) {
		UtilityFunctions::printerr("Couldn't allocate frames or packet for audio!");
		avcodec_flush_buffers(l_codec_ctx_audio);
		avcodec_free_context(&l_codec_ctx_audio);
		swr_free(&l_swr_ctx);
		return l_data;
	}

	// Set the seeker to the beginning
	int l_start_time = a_stream->start_time != AV_NOPTS_VALUE ? a_stream->start_time : 0;
	//avcodec_flush_buffers(l_codec_ctx_audio); // Not certain if needed here
	if ((response = av_seek_frame(a_format_ctx, -1, l_start_time, AVSEEK_FLAG_BACKWARD)) < 0) {
		UtilityFunctions::printerr("Can't seek to the beginning of audio stream!");
		avcodec_flush_buffers(l_codec_ctx_audio);
		avcodec_free_context(&l_codec_ctx_audio);
		swr_free(&l_swr_ctx);
		return l_data;
	}


	size_t l_audio_size = 0;
	int l_bytes_per_samples = av_get_bytes_per_sample(TARGET_FORMAT);

	while (!(get_frame(a_format_ctx, l_codec_ctx_audio, a_stream->index, l_frame, l_packet))) {
		// Copy decoded data to new frame
		l_decoded_frame->format = TARGET_FORMAT;
		l_decoded_frame->ch_layout = TARGET_LAYOUT;
		l_decoded_frame->sample_rate = TARGET_SAMPLE_RATE;
		l_decoded_frame->nb_samples = swr_get_out_samples(l_swr_ctx, l_frame->nb_samples);

		if ((response = av_frame_get_buffer(l_decoded_frame, 0)) < 0) {
			print_av_error("Couldn't create new frame for swr!", response);
			av_frame_unref(l_frame);
			av_frame_unref(l_decoded_frame);
			break;
		}

		if ((response = swr_convert_frame(l_swr_ctx, l_decoded_frame, l_frame)) < 0) {
			print_av_error("Couldn't convert the audio frame!", response);
			av_frame_unref(l_frame);
			av_frame_unref(l_decoded_frame);
			break;
		}

		size_t l_byte_size = l_decoded_frame->nb_samples * l_bytes_per_samples * 2;

		l_data.resize(l_audio_size + l_byte_size);
		memcpy(&(l_data.ptrw()[l_audio_size]), l_decoded_frame->extended_data[0], l_byte_size);
		l_audio_size += l_byte_size;

		av_frame_unref(l_frame);
		av_frame_unref(l_decoded_frame);
	}

	// Cleanup
	avcodec_flush_buffers(l_codec_ctx_audio);
	avcodec_free_context(&l_codec_ctx_audio);
	swr_free(&l_swr_ctx);

	av_frame_free(&l_frame);
	av_frame_free(&l_decoded_frame);
	av_packet_free(&l_packet);

	return l_data;
}

