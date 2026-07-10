{ signal: [
  { name: 'clk',          wave: 'p.......', period: 2 },
  { name: 'GPIO中断',     wave: '1.0......' },
  { name: 'intr_pending', wave: '1...0....' },
  { name: 'intr_accepted',wave: '0.1.0....' },
  { name: 'intr_taken',   wave: '0.1.0....' },
  { name: 'CSR写使能',    wave: '0.1.0....', data: 'mepc mcause mstatus' },
  { name: 'intr_flush',   wave: '0.1.0....' },
  { name: 'PC(IF阶段)',   wave: '=.=.=....', data: 'PC0  PC0+4  handler' },
  { name: 'shadow_save',  wave: '0...1.0..' },
  { name: 'x1-x31寄存器', wave: '=.....=..', data: '原始上下文  快照至影子寄存器' },
],
  head: { text: '恒定2周期中断响应时序' },
  foot: { text: ['GPIO触发', '', 'T0: 接受中断', '', 'T1: PC=handler', '', 'ISR进入IF'],
          tick: [0, 3, 5, 7, 9, 11, 13] },
  config: { hscale: 2 }
}