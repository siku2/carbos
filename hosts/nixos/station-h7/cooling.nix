{
  # Air comes in at the front and leaves at the back and through the radiator,
  # so both case fans follow the GPU. The Corsair runs the radiator fans itself.
  carbos.cooling = {
    sensors.gpu = {
      platform = "^amdgpu-pci-0300$";
      channel = 1;
    };

    curves.case = {
      sensor = "gpu";
      steps = [
        {
          temp = 60;
          speed = 0;
        }
        {
          temp = 70;
          speed = 30;
        }
        {
          temp = 85;
          speed = 100;
        }
      ];
    };

    fans = {
      front = {
        platform = "^nzxtsmart2-";
        channel = 1;
        curve = "case";
        minPwm = 64;
      };
      # A 3-pin fan in DC mode. It doesn't slow down below half.
      back = {
        platform = "^nzxtsmart2-";
        channel = 2;
        curve = "case";
        minPwm = 128;
      };
    };
  };
}
