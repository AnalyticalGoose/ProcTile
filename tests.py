
b_noise_rs = 6.0
b_noise_control_x = 0.29
b_noise_control_y = 0.71

b_noise_seed = 0.00
b_noise_contrast = 0.50

def tone_map(x):
    
    if (x <= b_noise_control_x):
        dx = x
        d = b_noise_control_x
        t = dx / d
        omt = (1.0 - t)
        omt2 = omt * omt
        t2 = t * t
        t3 = t2 * t
        d /= 3.0
        yac = d * b_noise_rs
        ybc = b_noise_control_y - d
        y2 = b_noise_control_y
    
        return (((yac * omt2) * t) * 3.0) + (((ybc * omt) * t2) * 3.0) + (y2 * t3)
    
    else:
        dx = x - b_noise_control_x
        d = 1.0 - b_noise_control_x
        t = dx / d
        omt = (1.0 - t)
        omt2 = omt * omt
        omt3 = omt2 * omt
        t2 = t * t
        t3 = t2 * t
        d /= 3.0
        y1 = b_noise_control_y
        yac = b_noise_control_y + d
          
        return (y1 * omt3) + (((yac * omt2) * t) * 3.0) + ((omt * t2) * 3.0) + t3








def run_test_suite():
    test_floats = [0.000, 1.000, 0.500, 0.192, 0.749, 0.29]
    test_answers = [0.0, 1.0, 0.8752483159221148, 0.610157090491615, 0.974259980190606, 0.71]

    tests_successful = True

    for i in range(len(test_floats)):
        res = tone_map(test_floats[i])
        if res != test_answers[i]:
            tests_successful = False
            print("Returned incorrect result for: " + str(test_floats[i]) + " - index " + str(i))
        
    if tests_successful:
        print("Tests successful")


run_test_suite()