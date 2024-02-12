// abreviations
//   fpc = fluidpitchconfidence
//   meta = metadata

Crooner {
  classvar sender, freq, conf, fluidPitch, s;
  classvar fpc_first_detected_pitch_voltage,fpc_last_detected_pitch_voltage,fpc_first_detected_pitch, fpc_last_detected_pitch;
  classvar <starting_voltage= -5, <ending_voltage=5,<sample_rate=1000, <voltage_segment_size=0.01;
  classvar <fpc_metadata, fpc_meta_num_voltage_segments, fpc_meta_current_voltage,fpc_meta_voltage_collect_incr=0.0001,fpc_meta_voltage_evaluate_incr=0.01, fpc_meta_voltage_evaluate_confidence_level = 0.3, fpc_meta_voltage_evaluate_confidence_hits=0, fpc_meta_sample_rate=1000, fpc_metadata_evaluating=false, fpc_metadata_collecting=false, tuning=false, fpc_metadata_evaluating_freqs, fpc_metadata_evaluating_voltages,
  fpc_metadata_found_first_frequency=false;
  classvar fpc_meta_samples_per_volt=10;
  
   *dynamicInit {
      if (fluidPitch == nil, {
        fluidPitch = Synth('FluidPitchDetector');
        fluidPitch.set(\crow_output,1);
        "dynamic init, fluidPitch synth created".postln;
      });
  }

  *initClass {
    StartUp.add {
      s = Server.default;
      OSCFunc.new({ |msg, time, addr, recvPort|
        Routine.new({
          var lua_sender = NetAddr.new("127.0.0.1",10111);     
          var sc_sender = NetAddr.new("127.0.0.1",57120); 
          
          SynthDef('FluidPitchDetector', {
            arg crow_output=1;
            var in = SoundIn.ar(0);
            # freq, conf = FluidPitch.kr(in,windowSize:1024);
            SendReply.kr(Impulse.kr(100), "/sc_crooner/update_freq_conf", [freq, conf]);
            SendReply.kr(Impulse.kr(100), "/sc_crooner/update_metadata_collect", [crow_output]);
            SendReply.kr(Impulse.kr(100), "/sc_crooner/update_metadata_evaluate", [crow_output,freq, conf]);
          }).add;

          s.sync;

          //////////////
          // send frequency and confidence data to lua 
          //////////////
          OSCFunc.new({ |msg, time, addr, recvPort|
            var frequency = msg[3];
            var confidence = msg[4];
            lua_sender.sendMsg("/lua_crooner/pitch_confidence", frequency, confidence);
          }, "/sc_crooner/update_freq_conf");

          //////////////
          // meta data collection 
          //////////////

          //start_metadata_collection
          OSCFunc.new({ |msg, time, addr, recvPort|
            fpc_meta_num_voltage_segments = (ending_voltage - starting_voltage) * sample_rate * voltage_segment_size;

            fpc_meta_voltage_collect_incr = 0.001;
            fpc_meta_sample_rate = 1000;
            starting_voltage= -5;
            ending_voltage=5;
            fpc_meta_current_voltage = starting_voltage;
            fpc_first_detected_pitch_voltage = nil;
            fpc_last_detected_pitch_voltage = nil;
            fpc_first_detected_pitch = nil;
            fpc_last_detected_pitch = nil;
            fpc_metadata_found_first_frequency = false;
            fpc_metadata_evaluating_freqs=nil;
            fpc_metadata_evaluating_voltages=nil;
            fpc_meta_voltage_evaluate_confidence_hits=0;
            
            fpc_metadata_evaluating_freqs=Array.new((ending_voltage - starting_voltage)/fpc_meta_voltage_evaluate_incr);
            fpc_metadata_evaluating_voltages=Array.new((ending_voltage - starting_voltage)/fpc_meta_voltage_evaluate_incr);

            fpc_metadata = [Dictionary.new(),Dictionary.new(),Dictionary.new(),Dictionary.new()];
            fpc_metadata.size.do({arg v,i;
              fpc_meta_samples_per_volt.do({arg v,j;
                fpc_metadata[i].put("voltage_samples"++((j+1)),[0,1,2,3]);
                fpc_metadata[i].put("confidence_samples"++((j+1)),[0,1,2,3]);
              });


              // fpc_meta_num_voltage_segments.do({arg v,j;
              //   fpc_metadata[i].put("voltage_segment_voltage"++((j+1)*voltage_segment_size),[0,1,2,3]);
              //   fpc_metadata[i].put("voltage_segment_confidence"++((j+1)*voltage_segment_size),[0,1,2,3]);
              // });
              
            });

            fpc_metadata_evaluating = true;

  
            ("start metadata collection "++fpc_metadata_evaluating).postln;  
          }, "/sc_crooner/start_metadata_collection");

          //update_metadata_evaluate
          OSCFunc.new({ |msg, time, addr, recvPort|
            var crow_output, voltage, frequency, confidence;
            var fpc_metadata_evaluating_freqs_sorted,fpc_metadata_last_freq_ix;
            var file,sorted_array_string;
            if (fpc_metadata_evaluating == true, {
              voltage=fpc_meta_current_voltage;
              frequency = msg[4];
              confidence = msg[5];
              switch(msg[3],
                1.0,{crow_output="1"},
                2.0,{crow_output="2"},
                3.0,{crow_output="3"},
                4.0,{crow_output="4"},
              );
              lua_sender.sendMsg("/lua_crooner/set_crow_voltage", crow_output, voltage);
              
              if (confidence > fpc_meta_voltage_evaluate_confidence_level, {
                if (fpc_first_detected_pitch_voltage.isNil.or( fpc_meta_voltage_evaluate_confidence_hits < 11), {
                  if (fpc_meta_voltage_evaluate_confidence_hits == 0, {
                    fpc_first_detected_pitch_voltage = voltage;
                    fpc_first_detected_pitch = frequency;
                    (["hit 0: ",fpc_first_detected_pitch_voltage, frequency,confidence]).postln;
                  });
                  fpc_meta_voltage_evaluate_confidence_hits = fpc_meta_voltage_evaluate_confidence_hits + 1;
                  if (fpc_meta_voltage_evaluate_confidence_hits == 10, {
                    (["found first frequency: ",fpc_first_detected_pitch_voltage, frequency,confidence,voltage]).postln;
                    fpc_metadata_found_first_frequency = true;
                  });
                });
              },{
                if ((fpc_meta_voltage_evaluate_confidence_hits > 0),{
                  "reset".postln;
                });
                fpc_meta_voltage_evaluate_confidence_hits = 0;
                fpc_first_detected_pitch_voltage = nil;
              });
              
              if (fpc_metadata_found_first_frequency == true, {
                var dupFreqCollection, foundDuplicates, numDuplicatesTarget=15;
                fpc_metadata_evaluating_freqs.add(frequency.round);
                fpc_metadata_evaluating_voltages.add(voltage);
                dupFreqCollection = Array.new(numDuplicatesTarget);
                numDuplicatesTarget.do({arg i; dupFreqCollection.add(frequency.round)});
                fpc_metadata_evaluating_freqs_sorted = Array.newFrom(fpc_metadata_evaluating_freqs);
                fpc_metadata_evaluating_freqs_sorted.sort;
                foundDuplicates = fpc_metadata_evaluating_freqs_sorted.find(dupFreqCollection);
                if ((foundDuplicates.isNumber).and(confidence > fpc_meta_voltage_evaluate_confidence_level), {
                  fpc_metadata_last_freq_ix = fpc_metadata_evaluating_freqs.find([frequency.round]);
                  fpc_last_detected_pitch = frequency;
                  fpc_last_detected_pitch_voltage = fpc_metadata_evaluating_voltages[fpc_metadata_last_freq_ix];

                  (["done evaluating (first/last frequency/voltage)",fpc_first_detected_pitch, fpc_last_detected_pitch, fpc_first_detected_pitch_voltage, fpc_last_detected_pitch_voltage]).postln;
                  fpc_metadata_evaluating=false;
                  // fpc_metadata_collecting = true;
                  lua_sender.sendMsg("/lua_crooner/set_crow_voltage", crow_output, fpc_last_detected_pitch_voltage);

                });

              });

              if (fpc_meta_current_voltage>5, {
                fpc_metadata_evaluating=false;
                // fpc_metadata_collecting = true;

              },{
                fpc_meta_current_voltage = fpc_meta_current_voltage + fpc_meta_voltage_evaluate_incr;
              });
              
            });
          }, "/sc_crooner/update_metadata_evaluate");

          //update_metadata_collection
          OSCFunc.new({ |msg, time, addr, recvPort|
            var crow_output, voltage, confidence;
            if (fpc_metadata_collecting == true, {
              voltage=fpc_meta_current_voltage;
              switch(msg[3],
                1.0,{crow_output="1"},
                2.0,{crow_output="2"},
                3.0,{crow_output="3"},
                4.0,{crow_output="4"},
              );
              //  ("update_metadata_collection " ++ fpc_metadata.size ++ "/" ++ fpc_meta_num_voltage_segments ++ "/" ++ fpc_meta_current_voltage).postln;
              lua_sender.sendMsg("/lua_crooner/set_crow_voltage", crow_output, voltage);
              fpc_meta_current_voltage = fpc_meta_current_voltage + fpc_meta_voltage_collect_incr;
              // fpc_meta_current_voltage.postln;
            });
          }, "/sc_crooner/update_metadata_collect");



          //////////////
          // tuner 
          //////////////

          OSCFunc.new({ |msg, time, addr, recvPort|
            "start pitch test".postln;  
            tuning=true;
          }, "/sc_crooner/start_tuner");

          OSCFunc.new({ |msg, time, addr, recvPort|
            "stop pitch test".postln;  
            tuning=false;
          }, "/sc_crooner/stop_tuner");

          Crooner.dynamicInit();
          lua_sender.sendMsg("/lua_crooner/sc_inited");

        }).play
      }, "/sc_crooner/init");

    }
  }

  free {
    ("free crooner objects").postln;
  }

}